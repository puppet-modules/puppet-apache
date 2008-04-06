# Some awstats defines and classes to be integrated into apache suppport
# Copyright (C) 2008 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.

class apache::awstats {

	package { [ "awstats", "libnet-dns-perl", "libnet-ip-perl", "libgeo-ipfree-perl", "libnet-xwhois-perl" ]:
		ensure => installed,
	}

}

define apache::awstats::domain() {
	cron { "awstats_update_${name}":
		command => "/usr/lib/cgi-bin/awstats.pl -config=blog.dasz.at",
		user => root,
		hour => 6,
		minute => 59
	}
}

