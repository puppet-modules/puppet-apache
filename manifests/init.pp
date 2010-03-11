# apache.pp - defines for apache
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
# 
# After http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe
# where Tim Stoop <tim.stoop@gmail.com> graciously posted this recipe
# modifications for multiple distros with support from <admin@immerda.ch>

import "awstats.pp"
import "site.pp"

$sites = "/etc/apache2/sites"
$mods = "/etc/apache2/mods"

class apache2 {
	err ("deprecated class usage, include 'apache' instead")
	include apache
}

class apache {
	include "apache::${operatingsystem}"
}

class apache::base {
	module_dir { [ "apache", "apache/mods", "apache/conf", "apache/sites" ]: }

	package {
		"apache":
			ensure => installed,
			before => Concat["/etc/apache2/ports.conf"];
	}

	service { apache:
		ensure => running,
		require => Package["apache"]
	}

	$apache_port_real = $apache_port ? { '' => 80, default => $apache_port }

	apache::port { "apache_class": port => $apache_port_real }

	# TODO: This has to be replaced by OS-specific configuration redirection
	# into $module_dir_path/apache
	include concat::setup
	concat {
		"/etc/apache2/ports.conf":
			mode => 644, owner => root, group => root,
	}
	file {
		"/etc/apache2/conf.d":
			ensure => directory, checksum => mtime,
			mode => 644, owner => root, group => root,
			require => Package[apache],
			notify => Exec["reload-apache"];
		"/etc/apache2/conf.d/charset":
			content => "# This really breaks many apps and pages otherwise\n# Disabled: AddDefaultCharset UTF-8\n",
			mode => 644, owner => root, group => root,
			require => Package[apache],
			notify => Exec["reload-apache"];
	}

	# always enable output compression
	apache::module { "deflate": ensure => present }

	# configure ssl
	case $apache_ssl {
		enabled: { 
			apache::module { "ssl": ensure => present }

			$apache_ssl_port_real = $apache_ssl_port ? { '' => 443, default => $apache_ssl_port }

			apache::port { "apache_ssl_class": port => $apache_ssl_port_real }

			file { "/etc/apache2/conf.d/ssl_puppet":
				content => "SSLCertificateFile /var/lib/puppet/ssl/certs/${fqdn}.pem\nSSLCertificateKeyFile /var/lib/puppet/ssl/private_keys/${fqdn}.pem\n",
				mode => 644, owner => root, group => root,
				require => Package["apache"], 
				notify => Exec["reload-apache"],
			}
		}
	}

	# Notify this when apache needs a reload. This is only needed when
	# sites are added or removed, since a full restart then would be
	# a waste of time. When the module-config changes, a force-reload is
	# needed.
	exec { "reload-apache":
		refreshonly => true,
		before => [ Service["apache"], Exec["force-reload-apache"] ],
		subscribe => [ File["${module_dir_path}/apache/mods"],
			File["${module_dir_path}/apache/conf"],
			File["${module_dir_path}/apache/sites"],
			File["/etc/apache2/ports.conf"] ]
	}

	exec { "force-reload-apache":
		refreshonly => true,
		before => Service["apache"],
	}

	# Monitoring stuff: munin and nagios
	$real_munin_stats_port = $munin_stats_port ? { '' => 8666, default => $munin_stats_port }
	apache::port { "apache::munin": port => $real_munin_stats_port }
	package { "libwww-perl": ensure => installed }
	apache::module { info: ensure => present }
	apache::site { munin-stats: ensure => present, content => template("apache/munin-stats"), }
	munin::plugin {
		[ "apache_accesses", "apache_processes", "apache_volume" ]:
			ensure => present,
			config => "env.url http://${hostname}:${real_munin_stats_port}/server-status?auto"
	}
	nagios::service { "http_${apache_port_real}":
		check_command => "http_port!${apache_port_real}"
	}

}

# Define an apache module. Debian packages place the module config
# into /etc/apache/mods-available.
#
# You can add a custom require (string) if the module depends on 
# packages that aren't part of the default apache package. Because of 
# the package dependencies, apache will automagically be included.
define apache::module ( $ensure = 'present', $require_package = 'apache' ) {
	case $ensure {
		'present' : {
			exec { "/usr/sbin/a2enmod $name":
				unless => "/bin/sh -c '[ -L ${mods}-enabled/${name}.load ] \\
					&& [ ${mods}-enabled/${name}.load -ef ${mods}-available/${name}.load ]'",
				notify => Exec["force-reload-apache"],
				require => Package[$require_package],
			}
		}
		'absent': {
			exec { "/usr/sbin/a2dismod $name":
				onlyif => "/bin/sh -c '[ -L ${mods}-enabled/${name}.load ] \\
					&& [ ${mods}-enabled/${name}.load -ef ${mods}-available/${name}.load ]'",
				notify => Exec["force-reload-apache"],
				require => Package["apache"],
			}
		}
	}
}

# Create a Listen directive for apache in ports.conf
# Use the $name to disambiguate between requests for the same port from
# different modules
define apache::port($port) {
	concat::fragment {
		"apache::port::${name}":
			target => "/etc/apache2/ports.conf",
			content => "Listen ${port}\n";
	}
}
