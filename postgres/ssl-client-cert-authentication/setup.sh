#!/bin/bash

# SET THIS TO BE YOUR DESIRED USERNAME
export MY_USER_NAME_FOR_CERT=`whoami`

# This directory is optional, but will use it to keep the CA root key safe
mkdir keys certs
chmod og-rwx keys certs

# Create a key-pair that will serve both as the root CA and the server key-pair
# the "ca.crt" name is used to match what it expects later
openssl req -new -x509 -days 365 -nodes -out certs/ca.crt \
  -keyout keys/ca.key -subj "/CN=root-ca"
cp certs/ca.crt pgconf/ca.crt

# Create the server key and CSR and sign with root key
openssl req -new -nodes -out server.csr \
  -keyout pgconf/server.key -subj "/CN=localhost"

openssl x509 -req -in server.csr -days 365 \
    -CA certs/ca.crt -CAkey keys/ca.key -CAcreateserial \
    -out pgconf/server.crt

# remove the CSR as it is no longer needed
rm server.csr


# lock down all the files in the pgconf mount
# in particular key/cert files must be locked down otherwise PostgreSQL won't
# enable SSL

sudo chown 70:70 pgconf/*.key pgconf/*.crt
sudo chmod 600 pgconf/server.key

docker-compose up -d

sleep 5

# create the client certificate
# by default, PostgreSQL will looks for these in the ~/.postgresql directory
# but we will do it a little differently in case you want to have certificates
# for logging into different PostgreSQL databases managed by different CAs
# NOTE: on a production system, you will not be storing your personal key next
# to the key of the CA. But on a production system, you would not be doing most
# of this setup ;-)
openssl req -new -nodes -out client.csr \
  -keyout keys/client.key -subj "/CN=${MY_USER_NAME_FOR_CERT}"
chmod og-rwx keys/*

openssl x509 -req -in client.csr -days 365 \
    -CA certs/ca.crt -CAkey keys/ca.key -CAcreateserial \
    -out certs/client.crt
rm client.csr


export PGSSLMODE="verify-full"
export PGSSLCERT="`pwd`/certs/client.crt"
export PGSSLKEY="`pwd`/keys/client.key"
export PGSSLROOTCERT="`pwd`/certs/ca.crt"
psql -h localhost -p 5432 -U $MY_USER_NAME_FOR_CERT postgres
