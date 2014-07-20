#!/usr/bin/perl -wT

use constant LDAP_SERVER => 'ldap1.ayl.ase.nai.org';
use constant BASE_DN     => 'dc=ase,dc=nai,dc=org';
use constant ROOT_CN     => 'cn=admin,dc=ase,dc=nai,dc=org';




###############################################################################
#
#          You probably don't need to piss around with anything
#          beyond this point in the file -- seriously. :-)
#
###############################################################################


use 5.6.1;
use strict;
use warnings;
use diagnostics;
use POSIX qw(strftime);

# Try and make sure we're semi-sane
umask 0022;
delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV TERM)};

# Take whatever constants are nicely defined above
my $ldapServer = LDAP_SERVER;
my $baseDn = BASE_DN;
my $rootCn = ROOT_CN;

# Run as l33t h4X0r r00t
die "You will need to run this script as r00t!" unless $> == 0;

# Install clients for Debian & Ubuntu machines
my $notRedHat = 1;
my $isDebian = 0;
if (-e '/etc/debian_version') {
	$isDebian = 1;
	system('apt-get install libnss-ldap libpam-ldap');

# Install clients for RHEL & Centos machines
} elsif (-e '/etc/redhat-release') {
	$notRedHat = 0;
	system('yum install openldap ss_ldap openldap-clients authconfig');
	system('authconfig '.
		' --useshadow --enableshadow '.
		' --usemd5 --enablemd5 '.
		' --enableldap --disableldaptls --enableldapauth '.
		" --ldapserver=$ldapServer ".
		" --ldapbasedn=$baseDn ".
		' --enablelocauthorize '.
		' --nostart --kickstart');

	addConfigToFile('/etc/pam.d/system-auth',	{
		'DingleDangFooBar'  => 'session     optional      pam_mkhomedir.so skel=/etc/skel umask=0022',
		});
}

# Move any old or example LDAP config files out of the way
backupFile(qw(/etc/ldap.conf /etc/libnss-ldap.conf /etc/pam_ldap.conf /etc/ldap.secret));

# Install the SSL certificate for TLS support
print "\nInstalling '/etc/ssl/certs/ca.cert' ...\n";
system('mkdir -p /etc/ssl/certs');
system('wget -O /etc/ssl/certs/ca.cert http://192.168.130.190/ca.cert');
chmod 0644, '/etc/ssl/certs/ca.cert';

# Create the bare bones ldap.conf
print "\nCreating '/etc/ldap.conf' ...\n";
if (open(FH,'>','/etc/ldap.conf')) {
	print FH <<EOT;
base $baseDn
host $ldapServer
ldap_version 3
ssl start_tls
tls_checkpeer yes
tls_cacertfile /etc/ssl/certs/ca.cert
EOT
	close(FH) || warn "Unable to close file '/etc/ldap.conf': $!";
} else {
	warn "Unable to open file '/etc/ldap.conf': $!";
}
chmod 0644, '/etc/ldap.conf' if -e '/etc/ldap.conf';

# Symlink /etc/libnss-ldap.conf to it just in case
print "\nSymlinking '/etc/libnss-ldap.conf' to '/etc/ldap.conf' ...\n";
symlink '/etc/ldap.conf', '/etc/libnss-ldap.conf';

# Symlink /etc/pam_ldap.conf to it just in case
print "\nSymlinking '/etc/pam_ldap.conf' to '/etc/ldap.conf' ...\n";
symlink '/etc/ldap.conf', '/etc/pam_ldap.conf';

# Add (a commented out) list of groups that can SSH to this server
#addConfigToFile('/etc/ssh/sshd_config',	{
#	'AllowGroups'  => '# AllowGroups infraadmins aseadmins fireperson root',
#	});

# Make sure the administrators can sudo on this server
#addConfigToFile('/etc/sudoers',	{
#	'%infraadmins' => '%infraadmins ALL=(ALL) ALL',
#	'%aseadmins'   => '%aseadmins ALL=(ALL) ALL',
#	'fireperson'   => 'fireperson ALL=(ALL) ALL',
#	});

# Try and write what we think we should have for Debian
if ($isDebian && $notRedHat) {
	replaceFile('/etc/pam.d/common-auth',
		"auth        sufficient    pam_unix.so nullok_secure\n".
		"auth        sufficient    pam_ldap.so use_first_pass\n"
		);
	replaceFile('/etc/pam.d/common-account',
		"account     sufficient    pam_unix.so\n".
		"account     sufficient    pam_ldap.so\n"
		);
	replaceFile('/etc/pam.d/common-password',
		"password    sufficient    pam_ldap.so ignore_unknown_user\n".
		"password    required      pam_unix.so nullok obscure min=4 max=8 md5\n"
		);
	replaceFile('/etc/pam.d/common-session',
		"session     required      pam_unix.so\n".
		"session     optional      pam_ldap.so\n".
		"session     optional      pam_mkhomedir.so skel=/etc/skel umask=0077\n"
		);

	# Make sure that the right things in /etc/nsswitch.conf
	# will use LDAP
	if (open(FH,'+<','/etc/nsswitch.conf')) {
		my @new;
		my $changed = 0;
                while (local $_ = <FH>) {
                        if (/^(passwd|group|shadow|protocols|services|ethers|netgroup):\s*(?!.*?\bldap\b)/) {
                                chomp;
                                push @new, "$_ ldap\n";
				$changed = 1;
                        } else {
				push @new, $_;
			}
                }
		if ($changed) {
			seek FH, 0, 0;
			print FH $_ for @new;
		}
                close(FH) || warn "Unable to close file '/etc/nsswitch.conf': $!";

	} else {
	        warn "Unable to open file '/etc/nsswitch.conf': $!"
	}
}

# Test that it works
print "\nYou should see the following line being returned from getent:\n";
print "testuser:x:10043:10005:testuser:/home/testuser:/bin/bash\n";
print "----- 8< -----\n";
system('getent passwd testuser');
print "----- 8< -----\n";

# Tell people what to do next
if ($notRedHat) {
	while (local $_ = <DATA>) {
		last if /__END__/;
		print $_;
	}
}

exit;

sub backupFile {
	my $bak = strftime('%Y%m%d-%H%M%S', localtime);
	for my $file (@_) {
		if (-f $file) {
			my $dest = "${file}-${bak}";
			print "Making backup of '$file' to '$dest' ...\n";
			rename $file, "${file}-${bak}";
			unlink $dest if -e $dest;
	
		} elsif (-e $file) {
			print "Removing old '$file' ...\n";
			unlink $file;
		}
	}
}

sub replaceFile {
	my ($file,$data)  = @_;
	return unless defined $file;
	return unless defined $data;
	backupFile($file) if -e $file;	

	if (open(FH,'>',$file)) {
		printf "\nCreating '%s' ...\n", $file;
		printf FH "\n\n\n# --BEGIN-- Automatically created by %s at %s\n",
			$0, scalar(localtime(time));
		print FH $data;
		printf FH "# --END-- Automatically created by %s at %s\n\n\n",
			$0, scalar(localtime(time));

		close(FH) || warn "Unable to close file '$file': $!";
	
	} else {
		warn "Unable to open file '$file': $!";
	}
}

sub addConfigToFile {
	my ($file,$config) = @_;
	return unless -e $file;
	return unless defined($config) && ref($config) eq 'HASH';

	if (open(FH,'+<',$file)) {
		while (local $_ = <FH>) {
			for my $line (keys %{$config}) {
				delete $config->{$line} if /^$line/;
			};
		}

		if (keys %{$config}) {
			printf "\nAdding %d lines of configuration to '%s' ...\n",
				scalar(values %{$config}), $file;

			printf FH "\n\n\n# --BEGIN-- Automatically added by %s at %s\n",
				$0, scalar(localtime(time));
			for my $authline (values %{$config}) {
				print FH "$authline\n";
			};
			printf FH "# --END-- Automatically added by %s at %s\n\n\n",
				$0, scalar(localtime(time));
		}

		close(FH) || warn "Unable to close file '$file': $!";

	} else {
		warn "Unable to open file '$file': $!";
	}
}

__DATA__

You do not appear to be running RedHat, so authconfig could not be used to
automatically configure your /etc/nsswitch.conf and /etc/pam.d/* configuration
files. Please use the following kruft as a guide to finishing your LDAP
configuration:

Add ldap in to /etc/nsswitch.conf for the following lookups:
   passwd, shadow, group
   protocols, services, netgroup, automount

egrep -v '^(\s*#.*|\s*)\$' /etc/pam.d/common-* <--- DEBIAN
    /etc/pam.d/common-auth: auth        sufficient    pam_unix.so nullok_secure
    /etc/pam.d/common-auth: auth        sufficient    pam_ldap.so use_first_pass
 /etc/pam.d/common-account: account     sufficient    pam_unix.so
 /etc/pam.d/common-account: account     sufficient    pam_ldap.so
/etc/pam.d/common-password: password    sufficient    pam_ldap.so ignore_unknown_user
/etc/pam.d/common-password: password    required      pam_unix.so nullok obscure min=4 max=8 md5
 /etc/pam.d/common-session: session     required      pam_unix.so
 /etc/pam.d/common-session: session     optional      pam_ldap.so
 /etc/pam.d/common-session: session     optional      pam_mkhomedir.so skel=/etc/skel umask=0077

egrep -v '^(\s*#.*|\s*)\$' /etc/pam.d/system-auth <--- REDHAT
auth        required      /lib/security/$ISA/pam_env.so
auth        sufficient    /lib/security/$ISA/pam_unix.so likeauth nullok
auth        sufficient    /lib/security/$ISA/pam_ldap.so use_first_pass
auth        required      /lib/security/$ISA/pam_deny.so
account     required      /lib/security/$ISA/pam_unix.so broken_shadow
account     sufficient    /lib/security/$ISA/pam_localuser.so
account     sufficient    /lib/security/$ISA/pam_succeed_if.so uid < 100 quiet
account     [default=bad success=ok user_unknown=ignore] /lib/security/$ISA/pam_ldap.so
account     required      /lib/security/$ISA/pam_permit.so
password    requisite     /lib/security/$ISA/pam_cracklib.so retry=3
password    sufficient    /lib/security/$ISA/pam_unix.so nullok use_authtok md5 shadow
password    sufficient    /lib/security/$ISA/pam_ldap.so use_authtok
password    required      /lib/security/$ISA/pam_deny.so
session     required      /lib/security/$ISA/pam_limits.so
session     required      /lib/security/$ISA/pam_unix.so
session     optional      /lib/security/$ISA/pam_ldap.so
session     optional      /lib/security/$ISA/pam_mkhomedir.so skel=/etc/skel umask=0022

__END__
