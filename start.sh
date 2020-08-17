#/bin/bash

################
### ZappaBoy ###
################

set -e

# Download Hyperledger Binaries (latest version)
curl -sSL http://bit.ly/2ysbOFE | bash -s -- 2.2.0 -d -s
rm -f config/configtx.yaml config/core.yaml config/orderer.yaml

# Generate crypto-materials for Orderer: create 'crypto-config' folder
export PATH=$PWD/bin:$PATH
cryptogen generate --config=./crypto-config.yaml

# Create folder structutre to store certs
ORG_DIR=$PWD/crypto-config/peerOrganizations/org1.example.com
PEER_DIR=$ORG_DIR/peers/peer0.org1.example.com
IDENTITY_REGISTRAR_DIR=$ORG_DIR/users/admin
TLS_REGISTRAR_DIR=$ORG_DIR/users/tlsadmin
ADMIN_DIR=$ORG_DIR/users/Admin@org1.example.com
mkdir -p $ORG_DIR/ca $ORG_DIR/tlsca $ORG_DIR/msp $PEER_DIR $IDENTITY_REGISTRAR_DIR $TLS_REGISTRAR_DIR $ADMIN_DIR

# (Root CA) Create folder structure for Identity Root CA
mkdir -p identity-rca/private identity-rca/certs identity-rca/newcerts identity-rca/crl
touch identity-rca/index.txt identity-rca/serial
echo 1000 > identity-rca/serial
echo 1000 > identity-rca/crlnumber

# Generate the Identity Root CA's
openssl ecparam -name prime256v1 -genkey -noout -out identity-rca/private/rca.identity.org1.example.com.key

# Based on the private key, generate a Certificate Signing Request (CSR) and self-sign the CSR
# In case the following command generate an error add this (https://github.com/openssl/openssl/issues/7754#issuecomment-601176195): 
# -config <(cat /etc/ssl/openssl.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/")
openssl req -config <(cat /etc/ssl/openssl_root-identity.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/") -new -x509 -sha256 -extensions v3_ca -key identity-rca/private/rca.identity.org1.example.com.key -out identity-rca/certs/rca.identity.org1.example.com.cert -days 3650 -subj "/C=IT/ST=Italy/L=Italy/O=org1.example.com/OU=Example/CN=rca.identity.org1.example.com"

# Create the TLS Root CA folder structure
mkdir -p tls-rca/private tls-rca/certs tls-rca/newcerts tls-rca/crl
touch tls-rca/index.txt tls-rca/serial
echo 1000 > tls-rca/serial
echo 1000 > tls-rca/crlnumber

# Based on the private key, generate a Certificate Signing Request (CSR) and self-sign the CSR
openssl ecparam -name prime256v1 -genkey -noout -out tls-rca/private/rca.tls.org1.example.com.key
openssl req -config <(cat openssl_root-tls.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/") -new -x509 -sha256 -extensions v3_ca -key tls-rca/private/rca.tls.org1.example.com.key -out tls-rca/certs/rca.tls.org1.example.com.cert -days 3650 -subj "/C=IT/ST=Italy/L=Italy/O=org1.example.com/OU=Example/CN=rca.tls.org1.example.com"

# (Intermediate CA) Create Intermediate Certificate Authorities
# Generate private key and CSR for Identity Intermediate CA. Note that the value of Organization (O) i.e. org1.example.com is the same as that of the Identity Root CA
openssl ecparam -name prime256v1 -genkey -noout -out $ORG_DIR/ca/ica.identity.org1.example.com.key
# In case the following command generate an error add this (https://github.com/openssl/openssl/issues/7754#issuecomment-601176195): 
# -config <(cat /etc/ssl/openssl.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/")
openssl req -config <(cat /etc/ssl/openssl.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/") -new -sha256 -key $ORG_DIR/ca/ica.identity.org1.example.com.key -out $ORG_DIR/ca/ica.identity.org1.example.com.csr -subj "/C=IT/ST=Italy/L=Italy/O=org1.example.com/OU=Example/CN=ica.identity.org1.example.com"

# The Identity Root CA signs the Identity Intermediate CA's CSR, issuing the certificate. The validity period is half that of the Root certificate. Note that we use v3_intermediate_ca extension. 
openssl ca -batch -config <(cat openssl_root-identity.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/") -extensions v3_intermediate_ca -days 1825 -notext -md sha256 -in $ORG_DIR/ca/ica.identity.org1.example.com.csr -out $ORG_DIR/ca/ica.identity.org1.example.com.cert

# Once we issue the identity intermediate CA's certificate, the Identity Root CA is not required anymore, unless there is a need to create another Intermediate CA or to revoke an Intermediate CA's certificate. 
# Create the "chain" file, which consists of both the Identity Intermediate CA's and Identity Root CA's certificate.
cat $ORG_DIR/ca/ica.identity.org1.example.com.cert $PWD/identity-rca/certs/rca.identity.org1.example.com.cert > $ORG_DIR/ca/chain.identity.org1.example.com.cert

# In a similar fashion, generate the certificate and key pairs for Intermediate TLS CA
openssl ecparam -name prime256v1 -genkey -noout -out $ORG_DIR/tlsca/ica.tls.org1.example.com.key
# In case the following command generate an error add this (https://github.com/openssl/openssl/issues/7754#issuecomment-601176195): 
# -config <(cat /etc/ssl/openssl.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/")
openssl req -new -sha256 -key $ORG_DIR/tlsca/ica.tls.org1.example.com.key -out $ORG_DIR/tlsca/ica.tls.org1.example.com.csr -subj "/C=IT/ST=Italy/L=Italy/O=org1.example.com/OU=Example/CN=ica.tls.org1.example.com"
openssl ca -batch -config <(cat openssl_root-tls.cnf | sed "s/RANDFILE\s*=\s*\$ENV::HOME\/\.rnd/#/") -extensions v3_intermediate_ca -days 1825 -notext -md sha256 -in $ORG_DIR/tlsca/ica.tls.org1.example.com.csr -out $ORG_DIR/tlsca/ica.tls.org1.example.com.cert
cat $ORG_DIR/tlsca/ica.tls.org1.example.com.cert $PWD/tls-rca/certs/rca.tls.org1.example.com.cert > $ORG_DIR/tlsca/chain.tls.org1.example.com.cert

# Finally, start the Intermediate CA. The configuration file of Intermediate CA will point to the certificate, key and chain which we generated in the previous steps. 
# Refer to ca-config/fabric-ca-server-config.yaml for the Identity CA instance and ca-config/tlsca/fabric-ca-server-config.yaml for the TLS CA instance
docker-compose up -d ica.org1.example.com

# Wait that the container is up                                                                                                                                                                                     
echo 'Waiting that constainer is up'
sleep 15

# Once the container is up and running, confirm that there are ca and tlsca instances running in the container
curl http://localhost:7054/cainfo\?ca\=ca
curl http://localhost:7054/cainfo\?ca\=tlsca

# Register and enroll users and peers for Org1, Wait at least 60 seconds before issuing the rest of the commands below. 
# This is a safety measure to ensure that NotBefore property of the issued certificates are not earlier the NotBefore property of the Intermediate CA Certificate
# As the Intermediate CA is ready, we can now create and sign user and peer certificates.
# Enroll the ca registrar user, admin. The registrar user has the privilege to register other users. 
# Notice the parameter --caname ca, which signifies interaction with the ca instance of the CA containers instead of tlsca
echo 'Waiting that Intermediate CA is ready'
sleep 70
export FABRIC_CA_CLIENT_HOME=$IDENTITY_REGISTRAR_DIR
fabric-ca-client enroll --caname ca --csr.names C=IT,ST=Italy,L=Italy,O=org1.example.com -m admin -u http://admin:adminpw@localhost:7054

sleep 5 
# Admin registers user Admin@org1.example.com, who is going to be the org1.example.com's admin, and peer peer0.org1.example.com
fabric-ca-client register --caname ca --id.name Admin@org1.example.com --id.secret adminpw --id.type admin --id.affiliation org1 -u http://localhost:7054
fabric-ca-client register --caname ca --id.name peer0.org1.example.com --id.secret mysecret --id.type peer --id.affiliation org1 -u http://localhost:7054

# Enroll Admin@org1.example.com
sleep 5
export FABRIC_CA_CLIENT_HOME=$ADMIN_DIR
fabric-ca-client enroll --caname ca --csr.names C=IT,ST=Italy,L=Italy,O=org1.example.com -m Admin@org1.example.com -u http://Admin@org1.example.com:adminpw@localhost:7054
cp $ORG_DIR/ca/chain.identity.org1.example.com.cert $ADMIN_DIR/msp/chain.cert
cp $PWD/nodeou.yaml $ADMIN_DIR/msp/config.yaml

# Enroll peer0.org1.example.com
export FABRIC_CA_CLIENT_HOME=$PEER_DIR
fabric-ca-client enroll --caname ca --csr.names C=IT,ST=Italy,L=Italy,O=org1.example.com -m peer0.org1.example.com -u http://peer0.org1.example.com:mysecret@localhost:7054
cp $ORG_DIR/ca/chain.identity.org1.example.com.cert $PEER_DIR/msp/chain.cert
cp $PWD/nodeou.yaml $PEER_DIR/msp/config.yaml

# Generate TLS certificate and key pair for peer0.org1.example.com to establish TLS sessions with other components. 
# There is no need to generate TLS certificate and key pair for Admin@org1.example.com as a user does not use any TLS communication. Notice that the parameter --caname is set to tlsca
export FABRIC_CA_CLIENT_HOME=$TLS_REGISTRAR_DIR
fabric-ca-client enroll --caname tlsca --csr.names C=IT,ST=Italy,L=Italy,O=org1.example.com -m admin -u http://admin:adminpw@localhost:7054
fabric-ca-client register --caname tlsca --id.name peer0.org1.example.com --id.secret mysecret --id.type peer --id.affiliation org1 -u http://localhost:7054
export FABRIC_CA_CLIENT_HOME=$PEER_DIR/tls
fabric-ca-client enroll --caname tlsca --csr.names C=IT,ST=Italy,L=Italy,O=org1.example.com -m peer0.org1.example.com -u http://peer0.org1.example.com:mysecret@localhost:7054
cp $PEER_DIR/tls/msp/signcerts/*.pem $PEER_DIR/tls/server.crt
cp $PEER_DIR/tls/msp/keystore/* $PEER_DIR/tls/server.key
cat $PEER_DIR/tls/msp/intermediatecerts/*.pem $PEER_DIR/tls/msp/cacerts/*.pem > $PEER_DIR/tls/ca.crt
rm -rf $PEER_DIR/tls/msp $PEER_DIR/tls/*.yaml

# Prepare org1.example.com's MSP folder.
mkdir -p $ORG_DIR/msp/admincerts $ORG_DIR/msp/intermediatecerts $ORG_DIR/msp/cacerts $ORG_DIR/msp/tlscacerts $ORG_DIR/msp/tlsintermediatecerts
cp $PEER_DIR/msp/cacerts/*.pem $ORG_DIR/msp/cacerts/
cp $PEER_DIR/msp/intermediatecerts/*.pem $ORG_DIR/msp/intermediatecerts/
cp $PWD/tls-rca/certs/rca.tls.org1.example.com.cert $ORG_DIR/msp/tlscacerts/
cp $ORG_DIR/tlsca/ica.tls.org1.example.com.cert $ORG_DIR/msp/tlsintermediatecerts/

cp $ORG_DIR/ca/chain.identity.org1.example.com.cert $ORG_DIR/msp/chain.cert
cp $PWD/nodeou.yaml $ORG_DIR/msp/config.yaml

# Create Orderer Genesis Block and Channel Transaction
export FABRIC_CFG_PATH=${PWD}
export CHANNELID='external-ca-channel'
configtxgen -profile OrdererGenesis -outputBlock ./config/genesis.block -channelID genesis-channel
configtxgen -profile Channel -outputCreateChannelTx ./config/${CHANNELID}.tx -channelID ${CHANNELID}

# Bring up Orderer, Peer and CLI
docker-compose up -d orderer.example.com peer0.org1.example.com cli
sleep 5

# Create channel and join peer0.org1.example.com to channel. 
# Note that the default user to perform all the operations from here onwards is Admin@org1.example.com, as specified in CORE_PEER_MSPCONFIGPATH environment variable in cli container.
docker exec cli peer channel create -o orderer.example.com:7050 --tls --cafile /var/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem -c ${CHANNELID} -f /config/${CHANNELID}.tx
sleep 5
docker exec cli peer channel join -b ${CHANNELID}.block
sleep 5

# Install and instantiate chaincode
# Install chaincode
docker exec cli peer chaincode install -n marbles -v 1.0 -l node -p /opt/gopath/src/github.com/marbles02/node -v 1.0
sleep 5

# Instantiate
docker exec cli peer chaincode instantiate -o orderer.example.com:7050 --tls --cafile /var/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem -C ${CHANNELID} -n marbles -l "node" -v 1.0 -c '{"Args":["init"]}' -P "OR('Org1MSP.member')"

sleep 5
# Attempt to invoke and query chaincode
# Invoke
docker exec cli peer chaincode invoke -o orderer.example.com:7050 --tls --cafile /var/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem -C ${CHANNELID} -n marbles -c '{"Args":["initMarble","marble2","red","50","tom"]}' --waitForEvent

sleep 5
# Query
docker exec cli peer chaincode query -C ${CHANNELID} -n marbles -c '{"Args":["readMarble","marble2"]}'

# If querying chaincode succeeds, we have successfully used the certificates to interact with the Hyperledger Fabric network

# To destroy Network and Root CA
# ./destroy.sh
