# apache2.pp - defines for apache2
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
# 
# After http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe
# where Tim Stoop <tim.stoop@gmail.com> graciously posted this recipe

$sites = "/etc/apache2/sites"
$mods = "/etc/apache2/mods"

class apache2 {

	package { apache2:
		ensure => installed,
	}

	service { apache2:
		ensure => running,
		pattern => "/usr/sbin/apache2",
		hasrestart => true,
		require => Package[apache2]
	}

	$apache2_port_real = $apache2_port ? { '' => 80, default => $apache2_port }

	file { "/etc/apache2/ports.conf":
		content => "Listen $apache2_port_real\n",
		mode => 644, owner => root, group => root,
		require => Package[apache2],
		notify => Exec["reload-apache2"],
	}

	nagios2::service { "http_$apache2_port_real":
		check_command => "http_port!$apache2_port_real"
	}

	case $apache2_ssl {
		enabled: { 
			apache2::module { "ssl": ensure => present }

			$apache2_ssl_port_real = $apache2_port ? { '' => 443, default => $apache2_ssl_port }
			file { "/etc/apache2/conf.d/ssl_puppet":
				content => "Listen $apache2_ssl_port_real\nSSLCertificateFile /etc/puppet/ssl/certs/$fqdn.pem\nSSLCertificateKeyFile /etc/puppet/ssl/private_keys/$fqdn.pem\n",
				mode => 644, owner => root, group => root,
				require => Package["apache2"], 
				notify => Exec["reload-apache2"],
			}
		}
	}

	# Notify this when apache needs a reload. This is only needed when
	# sites are added or removed, since a full restart then would be
	# a waste of time. When the module-config changes, a force-reload is
	# needed.
	exec { "reload-apache2":
		command => "/etc/init.d/apache2 reload",
		refreshonly => true,
		before => [ Service["apache2"], Exec["force-reload-apache2"] ]
	}

	exec { "force-reload-apache2":
		command => "/etc/init.d/apache2 force-reload",
		refreshonly => true,
		before => Service["apache2"],
	}

	# munin integration
	package { "libwww-perl": ensure => installed }
	config_file { "/etc/apache2/sites-available/munin-stats":
		content => template("apache/munin-stats"),
		require => Package["apache2"],
		notify => Exec["reload-apache2"]
	}
	module { info: ensure => present }
	site { munin-stats: ensure => present }
	munin::plugin {
		[ "apache_accesses", "apache_processes", "apache_volume" ]:
			ensure => present,
			config => "env.url http://${ipaddress}:${apache2_port_real}/server-status?auto"
	}

# defines from http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe

# Define an apache2 site. Place all site configs into
# /etc/apache2/sites-available and en-/disable them with this type.
#
# You can add a custom require (string) if the site depends on packages
# that aren't part of the default apache2 package. Because of the
# package dependencies, apache2 will automagically be included.
define site ( $ensure = 'present', $require = 'apache2' ) {
	case $ensure {
		'present' : {
			exec { "/usr/sbin/a2ensite $name":
				unless => "/bin/sh -c '[ -L ${sites}-enabled/$name ] \\
							&& [ ${sites}-enabled/$name -ef ${sites}-available/$name ]'",
				notify => Exec["reload-apache2"],
				require => Package[$require],
			}
		}
		'absent' : {
			exec { "/usr/sbin/a2dissite $name":
				onlyif => "/bin/sh -c '[ -L ${sites}-enabled/$name ] \\
							&& [ ${sites}-enabled/$name -ef ${sites}-available/$name ]'",
				notify => Exec["reload-apache2"],
				require => Package["apache2"],
			}
		}
		default: { err ( "Unknown ensure value: '$ensure'" ) }
	}
}

# Define an apache2 module. Debian packages place the module config
# into /etc/apache2/mods-available.
#
# You can add a custom require (string) if the module depends on 
# packages that aren't part of the default apache2 package. Because of 
# the package dependencies, apache2 will automagically be included.
define module ( $ensure = 'present', $require = 'apache2' ) {
	case $ensure {
		'present' : {
			exec { "/usr/sbin/a2enmod $name":
				unless => "/bin/sh -c '[ -L ${mods}-enabled/${name}.load ] \\
					&& [ ${mods}-enabled/${name}.load -ef ${mods}-available/${name}.load ]'",
				notify => Exec["force-reload-apache2"],
				require => Package[$require],
			}
		}
		'absent': {
			exec { "/usr/sbin/a2dismod $name":
				onlyif => "/bin/sh -c '[ -L ${mods}-enabled/${name}.load ] \\
					&& [ ${mods}-enabled/${name}.load -ef ${mods}-available/${name}.load ]'",
				notify => Exec["force-reload-apache2"],
				require => Package["apache2"],
			}
		}
		default: { err ( "Unknown ensure value: '$ensure'" ) }
	}
}

class no_default_site inherits apache2 {
	exec { "/usr/sbin/a2dissite default":
		onlyif => "/usr/bin/test -L /etc/apache2/sites-enabled/000-default",
		notify => Exec["reload-apache2"],
	}
}

}
