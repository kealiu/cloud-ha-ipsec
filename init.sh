#!/bin/bash
# Copyright 2024 ke.liu#foxmail.com

# let's go into $HOME
cd ${HOME}

# curl is so slowly, use `aria2` for big file download
apt-get update && apt-get install -y keepalived strongswan curl jq unzip aria2

# install latest aws cli
which aws
if [ "$?" == "1" ] ; then
    aria2c "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update    
fi

# setup region
MY_REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
aws configure set default.region ${MY_REGION}

# enable forwarding

if [ "$(sysctl -n net.ipv4.ip_forward)" == "0" ] ; then
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    sysctl -p
fi

#########
# the truely work script
#########

# pause a moment to avoid some trick IAM role state
sleep 15

# if role is not working properly, let's reboot it
aws sts get-caller-identity
if [ "$?" != "0" ] ; then
    rm -rf /var/lib/cloud/instances/*/sem/config_scripts_user
    echo "FITAL ERROR!! IAM ROle not working! TRY re-apply the instance IAM role in AWS web console"
    sleep 60
    reboot
fi

# gather information
MY_PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
MY_MAC_ADDR=$(curl http://169.254.169.254/latest/meta-data/mac)
MY_ENI=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MY_MAC_ADDR}/interface-id)
MY_VPC_ID=$(curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MY_MAC_ADDR}/vpc-id)
MY_INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

# setup AK/SK
#MY_CRED=$(curl http://169.254.169.254/latest/meta-data/iam/security-credentials/ha-ipsec-role)
#export AWS_ACCESS_KEY_ID=$(echo ${MY_CRED}| jq -r '.AccessKeyId')
#export AWS_SECRET_ACCESS_KEY=$(echo ${MY_CRED}| jq -r '.SecretAccessKey')
#export AWS_SESSION_TOKEN=$(echo ${MY_CRED}| jq -r '.Token')

# get parameters
MY_PEER_ID=$(aws ssm get-parameter --name "/ha-ipsec/${MY_INSTANCE_ID}" | jq -r '.Parameter.Value' | jq -r '.peer')
MY_PEER_CONFIG=$(aws ssm get-parameter --name "/ha-ipsec/${MY_PEER_ID}" | jq -r '.Parameter.Value')

MY_PEER_IP=$(echo ${MY_PEER_CONFIG} | jq -r '.ip')
MY_PEER_ENI=$(echo ${MY_PEER_CONFIG} | jq -r '.eni')
MY_STATUS=$(echo ${MY_PEER_CONFIG} | jq -r '.status')
MY_TOPIC=$(echo ${MY_PEER_CONFIG} | jq -r '.sns')

# create switchover script
cat > /usr/local/bin/master.sh << EoF
#!/bin/bash
ENDSTATE=$3
NAME=$2
TYPE=$1

if [ "${ENDSTATE}" != "MASTER" ] ; then
        echo "$(date +'%D-%X.%N') enter ${ENDSTATE} mode" >> /tmp/keepalived-script.log
        sleep 5
        exit
fi
echo "\$(date +'%D %X.%N') start switchover to master" >> /tmp/keepalived-script.log
VPCRTTBL=\$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=${MY_VPC_ID})
for rt in \$(echo \${VPCRTTBL} | jq -r -c '.RouteTables[] | select(.Routes[]?.NetworkInterfaceId=="${MY_PEER_ENI}")');
do
    rtid=\$(echo \${rt} | jq -r '.RouteTableId')
    for item in \$(echo \${rt} | jq -r -c '.Routes[] | select(.NetworkInterfaceId=="${MY_PEER_ENI}")');
    do
        rtcidr=\$(echo \${item} | jq -r '.DestinationCidrBlock')
        aws ec2 replace-route --route-table-id \${rtid} --destination-cidr-block \${rtcidr} --network-interface-id ${MY_ENI}
    done
done

aws sns publish --topic-arn "${MY_TOPIC}" --message "${MY_INSTANCE_ID}/${MY_PRIVATE_IP} changed to MASTER"

echo "\$(date +'%D %X.%N') end switchover to master" >> /tmp/keepalived-script.log
EoF

chmod a+x /usr/local/bin/master.sh

# create keepalived config
cat > /etc/keepalived/keepalived.conf << EoF
global_defs {
    script_user ubuntu
    enable_script_security
}

vrrp_track_process ipsec {
    process charon
}

vrrp_instance VI_1 {
    debug 2
    interface ens5 # interface to monitor
    state ${MY_STATUS}
    virtual_router_id 51 # Assign one ID for this route
    priority 199 # 199 on master, 100 on backup
    unicast_src_ip ${MY_PRIVATE_IP} # My IP
    unicast_peer {
        ${MY_PEER_IP}  # peer IP
    }

    track_process {
         ipsec
    }

    notify "/usr/local/bin/master.sh"
}
EoF

# make everything start
systemctl restart keepalived

# make this script run on startup everytime
rm -rf /var/lib/cloud/instances/*/sem/config_scripts_user
