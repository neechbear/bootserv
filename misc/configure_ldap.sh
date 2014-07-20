#!/bin/bash

bak=`date +%Y%m%d`
umask 0022

# Run as l33t h4X0r r00t
if [ "X`id -u`" != "X0" ]; then
	echo "You will need to run this script as r00t!"
	exit 1
fi

# Install clients for Debian & Ubuntu machines
if test -e "/etc/debian_version"; then
	apt-get install libnss-ldap libpam-ldap

# Install clients for RHEL & Centos machines
elif test -e "/etc/redhat-release"; then
	yum install openldap ss_ldap openldap-clients authconfig
	authconfig \
		--useshadow --enableshadow \
		--usemd5 --enablemd5 \
		--enableldap --disableldaptls --enableldapauth \
		--ldapserver=ldap1.ayl.ase.nai.org \
		--ldapbasedn=dc=ase,dc=nai,dc=org \
		--enablelocauthorize \
		--nostart --kickstart
fi

# Move any old or example LDAP config files out of the way
for file in /etc/ldap.conf /etc/libnss-ldap.conf /etc/pam_ldap.conf /etc/ldap.secret
do
	if test -f "$file"; then
		echo "Making backup of '$file' to '${file}-${bak}' ..."
		mv "$file" "${file}-${bak}"
	elif test -e "$file"; then
		echo "Removing old '$file' ..."
		rm "$file"
	fi
done

# Install the SSL certificate for TLS support
echo "Installing '/etc/ssl/certs/ca.cert' ..."
mkdir -p /etc/ssl/certs
wget -O /etc/ssl/certs/ca.cert http://192.168.130.190/ca.cert
chmod 644 /etc/ssl/certs/ca.cert

# Create the bare bones ldap.conf
echo "Creating '/etc/ldap.conf' ..."
cat >/etc/ldap.conf <<EOT
base dc=ase,dc=nai,dc=org
host ldap1.ayl.ase.nai.org
ldap_version 3
ssl start_tls
tls_checkpeer yes
tls_cacertfile /etc/ssl/certs/ca.cert
EOT
chmod 644 /etc/ldap.conf

# Symlink /etc/libnss-ldap.conf to it just in case
echo "Symlinking '/etc/libnss-ldap.conf' to '/etc/ldap.conf' ..."
ln -s /etc/ldap.conf /etc/libnss-ldap.conf

# Symlink /etc/pam_ldap.conf to it just in case
echo "Symlinking '/etc/pam_ldap.conf' to '/etc/ldap.conf' ..."
ln -s /etc/ldap.conf /etc/pam_ldap.conf

# Add ldap in to /etc/nsswitch.conf for:
#   passwd, shadow, group
#   protocols, services, netgroup, automount

# Update in /etc/pam.d:
#   system-auth (RHEL)
#   common-account (Debian)
#   common-auth (Debian)
#   common-password (Debian)
#   common-session (Debian)

#[root@ns1 ~]# egrep -v '^(\s*#.*|\s*)$' /etc/pam.d/system-auth
#auth        required      /lib/security/$ISA/pam_env.so
#auth        sufficient    /lib/security/$ISA/pam_unix.so likeauth nullok
#auth        sufficient    /lib/security/$ISA/pam_ldap.so use_first_pass
#auth        required      /lib/security/$ISA/pam_deny.so
#account     required      /lib/security/$ISA/pam_unix.so broken_shadow
#account     sufficient    /lib/security/$ISA/pam_localuser.so
#account     sufficient    /lib/security/$ISA/pam_succeed_if.so uid < 100 quiet
#account     [default=bad success=ok user_unknown=ignore] /lib/security/$ISA/pam_ldap.so
#account     required      /lib/security/$ISA/pam_permit.so
#password    requisite     /lib/security/$ISA/pam_cracklib.so retry=3
#password    sufficient    /lib/security/$ISA/pam_unix.so nullok use_authtok md5 shadow
#password    sufficient    /lib/security/$ISA/pam_ldap.so use_authtok
#password    required      /lib/security/$ISA/pam_deny.so
#session     required      /lib/security/$ISA/pam_limits.so
#session     required      /lib/security/$ISA/pam_unix.so
#session     optional      /lib/security/$ISA/pam_ldap.so
#session     optional      /lib/security/$ISA/pam_mkhomedir.so skel=/etc/skel umask=0022
#[root@ns1 ~]# 

#skathi:/etc/pam.d# egrep -v '^(\s*#.*|\s*)$' /etc/pam.d/common-*            
#/etc/pam.d/common-account:account       sufficient      pam_unix.so
#/etc/pam.d/common-account:account sufficient      pam_ldap.so
#/etc/pam.d/common-auth:auth    sufficient      pam_unix.so nullok_secure
#/etc/pam.d/common-auth:auth    sufficient      pam_ldap.so try_first_pass
#/etc/pam.d/common-password:password   sufficient   pam_unix.so nullok obscure min=4 max=8 md5
#/etc/pam.d/common-password:password   sufficient   pam_ldap.so use_authtok
#/etc/pam.d/common-session:session       sufficient      pam_unix.so
#/etc/pam.d/common-session:session       sufficient      pam_ldap.so
#/etc/pam.d/common-session:session optional        pam_mkhomedir.so skel=/etc/skell umask=0077
#skathi:/etc/pam.d# 


# Test that it works
echo "You should see the following line being returned from getent:"
echo "testuser:x:1043:1008:testuser:/home/testuser:/bin/bash"
echo "----- 8< -----"
getent passwd testuser
echo "----- 8< -----"

