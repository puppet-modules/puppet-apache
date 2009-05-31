# site.pp - define a (virtual hosting) site for apache
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
# 
# After http://reductivelabs.com/trac/puppet/wiki/Recipes/DebianApache2Recipe
# where Tim Stoop <tim.stoop@gmail.com> graciously posted this recipe
# modifications for multiple distros with support from <admin@immerda.ch>

# Define an apache site from a file.
#
# You can add a custom require_package string if the site depends on packages
# that aren't part of the default apache package.
#
# The parameters ensure, content and source behave like their respective
# counterparts on the File type.
define apache::site ( $ensure = 'present', $require_package = 'apache', $content = '', $source = '') {
	include apache

	$site_file = "${module_dir_path}/apache/sites/${name}"
	config_file {
		$site_file:
			ensure => $ensure,
			content => $content,
			source => $source,
			notify => Exec["reload-apache"]
	}

	# remove legacy sites from debian
	file {
		"/etc/apache2/sites-available/${name}":
			notify => Exec["reload-apache"],
			ensure => absent;
		"/etc/apache2/sites-enabled/${name}":
			notify => Exec["reload-apache"],
			ensure => absent;
	}
}
