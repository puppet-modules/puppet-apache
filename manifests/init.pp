# apache2.pp - defines for apache2
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
# 
# After http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe
# where Tim Stoop <tim.stoop@gmail.com> graciously posted this recipe

$sites = "/etc/apache2/sites"
$mods = "/etc/apache2/mods"

class apache2 {

	package { apache2, libapache2-mod-auth-pam:
		ensure => installed,
	}

	service { apache2:
		ensure => running,
		pattern => "/usr/sbin/apache2",
		hasrestart => true,
		require => Package[apache2]
	}

	$apache2_port_real = $apache2_port ? { '' => 80, default => $apache2_port }

	file {
		"/etc/apache2/ports.conf":
			content => "Listen $apache2_port_real\n",
			mode => 644, owner => root, group => root,
			require => Package[apache2],
			notify => Exec["reload-apache2"];
		"/etc/apache2/conf.d":
			ensure => directory, checksum => mtime,
			mode => 644, owner => root, group => root,
			require => Package[apache2],
			notify => Exec["reload-apache2"];
		"/etc/apache2/conf.d/charset":
			content => "# This really breaks many apps and pages otherwise\n# Disabled: AddDefaultCharset UTF-8\n",
			mode => 644, owner => root, group => root,
			require => Package[apache2],
			notify => Exec["reload-apache2"];
	}

	nagios2::service { "http_$apache2_port_real":
		check_command => "http_port!$apache2_port_real"
	}

	# configure ssl
	case $apache2_ssl {
		enabled: { 
			apache2::module { "ssl": ensure => present }

			$apache2_ssl_port_real = $apache2_ssl_port ? { '' => 443, default => $apache2_ssl_port }
			file { "/etc/apache2/conf.d/ssl_puppet":
				content => "Listen $apache2_ssl_port_real\nSSLCertificateFile /var/lib/puppet/ssl/certs/$fqdn.pem\nSSLCertificateKeyFile /var/lib/puppet/ssl/private_keys/$fqdn.pem\n",
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
	$real_munin_stats_port = $munin_stats_port ? { '' => 8666, default => $munin_stats_port }
	package { "libwww-perl": ensure => installed }
	module { info: ensure => present }
	site { munin-stats: ensure => present, content => template("apache/munin-stats"), }
	munin::plugin {
		[ "apache_accesses", "apache_processes", "apache_volume" ]:
			ensure => present,
			config => "env.url http://${hostname}:${real_munin_stats_port}/server-status?auto"
	}

# defines from http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe

# Define an apache2 site. Place all site configs into
# /etc/apache2/sites-available and en-/disable them with this type.
#
# You can add a custom require (string) if the site depends on packages
# that aren't part of the default apache2 package. Because of the
# package dependencies, apache2 will automagically be included.
#
# With the optional parameter "content", the site config can be provided
# directly (e.g. with template()). Alternatively "source" is used as a standard
# File%source URL to get the site file. The third possiblity is setting
# "ensure" to a filename, which will be symlinked.
define site ( $ensure = 'present', $require_package = 'apache2', $content = '', $source = '') {

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
							notify => [ Exec["a2site-${name}"], Exec["reload-apache2"] ];
					}
				}
				default: {
					file { 
						$available_file:
							ensure => $ensure,
							source => $source,
							mode => 0664, owner => root, group => root,
							notify => [ Exec["a2site-${name}"], Exec["reload-apache2"] ];
					}
				}
			}
		}
		default: {
			file { $available_file:
				ensure => $ensure,
				content => $content,
				mode => 0664, owner => root, group => root,
				notify => [ Exec["a2site-${name}"], Exec["reload-apache2"] ];
			}
		}
	}

	file {
		$enabled_file:
			ensure => $enabled_file_ensure,
			mode => 0664, owner => root, group => root,
			require => Exec["a2site-${name}"],
			notify => Exec["reload-apache2"];
	}

	exec { $a2site_exec:
		refreshonly => true,
		notify => Exec["reload-apache2"],
		require => Package[$require_package],
		alias => "a2site-${name}"
	}

}

# Define an apache2 module. Debian packages place the module config
# into /etc/apache2/mods-available.
#
# You can add a custom require (string) if the module depends on 
# packages that aren't part of the default apache2 package. Because of 
# the package dependencies, apache2 will automagically be included.
define module ( $ensure = 'present', $require_package = 'apache2' ) {
	case $ensure {
		'present' : {
			exec { "/usr/sbin/a2enmod $name":
				unless => "/bin/sh -c '[ -L ${mods}-enabled/${name}.load ] \\
					&& [ ${mods}-enabled/${name}.load -ef ${mods}-available/${name}.load ]'",
				notify => Exec["force-reload-apache2"],
				require => Package[$require_package],
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
	# Don't use site here, because the default site ships with a
	# non-default symlink. Oh, the irony!
	exec { "/usr/sbin/a2dissite default":
		onlyif => "/usr/bin/test -L /etc/apache2/sites-enabled/000-default",
		notify => Exec["reload-apache2"],
	}
}

}
