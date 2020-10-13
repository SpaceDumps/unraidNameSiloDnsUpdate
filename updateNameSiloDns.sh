#!/bin/bash

###########################################################################################
# UnRaid NameSilo DNS Update Script
# Written by: SpaceDumps
# 
# This script will lookup all the DNS Records of one domain managed through NameSilo, and
# send an update for any A-type record where the IP address in the DNS Record does not
# match the IP address of the UnRaid box running this script. (The source IP address is
# determined from the API response itself rather than typical Linux DNS resolution 
# methods, as UnRaid does not natively support nslookup/dig/etc. 
# 
# To manually browse your NameSilo DNS Records, go to:
#                          https://www.namesilo.com/account_domain_manage_dns.php
# 
# 
# USE:  Create a new script in the User Scripts plugin and paste this file as-is
# as that script's code. Fill in the DOMAIN and APIKEY variables with your own. Set the
# script to run regularly.
###########################################################################################

echo "#################################################################################"
echo "######################## NameSilo DNS Update Script #############################"
echo "$(date +%F+%T)"

##Domain name:
DOMAIN="mydomain.com"   #replace this with your domain managed with NameSilo

##APIKEY obtained from Namesilo:
APIKEY="1a2b3c4d5e6f7g8h9i"  #replace this with your NameSilo API key 


##Temporary files for storing API responses
RECORDSXML="/tmp/user.scripts/namesiloRecordsRsp.xml"
UPDATERSPXML="/tmp/user.scripts/namesiloUpdateRsp.xml"

### Fetch & Update DNS Records from NameSilo

echo "Fetching $DOMAIN DNS records from NameSilo"

# Delete the response file (if it exists) and create a blank one
if [[ -f "$RECORDSXML" ]]; then
    rm -f $RECORDSXML
fi
echo "" > $RECORDSXML

# echo "DEBUG | https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=$APIKEY&domain=$DOMAIN"
curl -s "https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=$APIKEY&domain=$DOMAIN" > $RECORDSXML

RCODE=$(grep -oP '(?<=<code>).*?(?=</code>)' $RECORDSXML)
if [ ! $RCODE -eq 300 ]; then 
    echo "ERROR: Https request for DNS records returned code $RCODE"
    echo ""
    echo "Full XML of response:"
    echo ""
    cat $RECORDSXML
    exit 1
fi

SRCIP=$(grep -oP '(?<=<ip>).*?(?=</ip>)' $RECORDSXML)

### DEBUG: uncomment to list all the DNS records received before processing them
# for i in $(grep -oP '(?<=<resource_record>).*?(?=</resource_record>)' $RECORDSXML); do
#     echo $i
# done
###

# Loop through each DNS record
# Format: <record_id><type><host><value><ttl><distance>
y=0
for i in $(grep -oP '(?<=<resource_record>).*?(?=</resource_record>)' $RECORDSXML); do
    # Check type
    case $(echo $i | grep -oP '(?<=<type>).*?(?=</type>)') in
      A)
        if [[ $(echo $i | grep -oP '(?<=<value>).*?(?=</value>)') == $SRCIP ]]; then 
            echo "[$y] Source and DNS Record IP addresses match. No update needed."
        else
            echo "[$y] Mismatch b/w source and DNS Record! Updating..."
            
            VALUE=$(echo $i | grep -oP '(?<=<value>).*?(?=</value>)')
            RECORD_ID=$(echo $i | grep -oP '(?<=<record_id>).*?(?=</record_id>)')
            TTL=$(echo $i | grep -oP '(?<=<ttl>).*?(?=</ttl>)')
            HOST=$(echo $i | grep -oP '(?<=<host>).*?(?=</host>)')
            SUBDOMAIN=${HOST/%$DOMAIN}
            SUBDOMAIN=${SUBDOMAIN/%"."}
            
            # Delete the response file (if it exists) and create a blank one
            if [[ -f "$UPDATERSPXML" ]]; then
                rm -f $UPDATERSPXML
            fi
            echo "" > $UPDATERSPXML
            
            # Send DNS update
            curl -s "https://www.namesilo.com/api/dnsUpdateRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrid=$RECORD_ID&rrhost=$SUBDOMAIN&rrvalue=$SRCIP&rrttl=$TTL" > $UPDATERSPXML

            URCODE=$(grep -oP '(?<=<code>).*?(?=</code>)' $UPDATERSPXML)
            if [ ! $URCODE -eq 300 ]; then 
                echo "ERROR: DNS update returned code $URCODE"
                echo ""
                echo "Full XML of response:"
                echo ""
                cat $UPDATERSPXML
                exit 1
            else
                echo "[$y] ...record updated successfully:  $VALUE --> $SRCIP"
            fi

        fi
      ;;
      MX)
        echo "[$y] Skipping MX record"
      ;;
      *)
        echo "[$y] Unknown record type: $i"
      ;;
    esac
    y=$(($y + 1))
done




### Post-Cleanup

# Delete the response file (comment this out to be able to manually browse the responses for debugging)
rm -f $RECORDSXML

echo "Script finished."

exit 0


