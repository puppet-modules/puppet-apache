# apache.pp - defines for apache
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
# 
# After http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe
# where Tim Stoop <tim.stoop@gmail.com> graciously posted this recipe
# modifications for multiple distros with support from <admin@immerda.ch>

import "awstats.pp"

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
	modules_dir { "apache": }

	package {
		"apache": ensure => installed;
		# TODO: refactor away, this is not part of the LCD
		"libapache-mod-auth-pam": ensure => installed,
	}

	service { apache:
		ensure => running,
		require => Package["apache"]
	}

	$apache_port_real = $apache_port ? { '' => 80, default => $apache_port }

	# TODO: This has to be replaced by OS-specific configuration redirection
	# into $modules_dir/apache
	file {
		"/etc/apache2/ports.conf":
			content => "Listen $apache_port_real\n",
			mode => 644, owner => root, group => root,
			require => Package[apache],
			notify => Exec["reload-apache"];
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

	# configure ssl
	case $apache_ssl {
		enabled: { 
			apache::module { "ssl": ensure => present }

			$apache_ssl_port_real = $apache_ssl_port ? { '' => 443, default => $apache_ssl_port }
			file { "/etc/apache2/conf.d/ssl_puppet":
				content => "Listen ${apache_ssl_port_real}\nSSLCertificateFile /var/lib/puppet/ssl/certs/${fqdn}.pem\nSSLCertificateKeyFile /var/lib/puppet/ssl/private_keys/${fqdn}.pem\n",
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
		before => [ Service["apache"], Exec["force-reload-apache"] ]
	}

	exec { "force-reload-apache":
		refreshonly => true,
		before => Service["apache"],
	}

	# Monitoring stuff: munin and nagios
	$real_munin_stats_port = $munin_stats_port ? { '' => 8666, default => $munin_stats_port }
	package { "libwww-perl": ensure => installed }
	module { info: ensure => present }
	site { munin-stats: ensure => present, content => template("apache/munin-stats"), }
	munin::plugin {
		[ "apache_accesses", "apache_processes", "apache_volume" ]:
			ensure => present,
			config => "env.url http://${hostname}:${real_munin_stats_port}/server-status?auto"
	}
	nagios2::service { "http_${apache_port_real}":
		check_command => "http_port!${apache_port_real}"
	}

}

# defines from http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianapacheRecipe

# Define an apache site. Place all site configs into
# /etc/apache/sites-available and en-/disable them with this type.
#
# You can add a custom require (string) if the site depends on packages
# that aren't part of the default apache package. Because of the
# package dependencies, apache will automagically be included.
#
# With the optional parameter "content", the site config can be provided
# directly (e.g. with template()). Alternatively "source" is used as a standard
# File%source URL to get the site file. The third possiblity is setting
# "ensure" to a filename, which will be symlinked.
define apache::site ( $ensure = 'present', $require_package = 'apache', $content = '', $source = '') {

	$available_file = "${sites}-available/${name}"
	$enabled_file = "${sites}-enabled/${name}"
	$enabled_file_ensure = $ensure ? { 'absent' => 'absent', default => "${sites}-available/${name}" }
	$a2site_exec = $ensure ? { 'absent' => "/usr/sbin/a2dissite ${name}", 'present' => "/usr/sbin/a2ensite ${name}" }

	case $content {
		'': {
			case $source {
				'': {
					file {
						$available_file:
							ensure => $ensure,
							mode => 0664, owner => root, group => root,
							notify => [ Exec["a2site-${name}"], Exec["reload-apache"] ];
					}
				}
				default: {
					file { 
						$available_file:
							ensure => $ensure,
							source => $source,
							mode => 0664, owner => root, group => root,
							notify => [ Exec["a2site-${name}"], Exec["reload-apache"] ];
					}
				}
			}
		}
		default: {
			file { $available_file:
				ensure => $ensure,
				content => $content,
				mode => 0664, owner => root, group => root,
				notify => [ Exec["a2site-${name}"], Exec["reload-apache"] ];
			}
		}
	}

	file {
		$enabled_file:
			ensure => $enabled_file_ensure,
			mode => 0664, owner => root, group => root,
			require => Exec["a2site-${name}"],
			notify => Exec["reload-apache"];
	}

	exec { $a2site_exec:
		refreshonly => true,
		notify => Exec["reload-apache"],
		require => Package[$require_package],
		alias => "a2site-${name}"
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
		default: { err ( "Unknown ensure value: '$ensure'" ) }
	}
}

# disable the default site on debian
class apache::no_default_site inherits apache {
	# Don't use site here, because the default site ships with a
	# non-default symlink. Oh, the irony!
	exec { "/usr/sbin/a2dissite default":
		onlyif => "/usr/bin/test -L /etc/apache/sites-enabled/000-default",
		notify => Exec["reload-apache"],
	}
}

