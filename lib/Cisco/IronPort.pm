package Cisco::IronPort;

use strict;
use warnings;

use LWP;
use Carp qw(croak);

our $VERSION 	= '0.05';
our @RANGES	= qw (current_hour current_day);
our %M_MAP	= (
		top_users_by_clean_outgoing_messages 	=> {
							report_query	=> 'mga_internal_users_top_outgoing_messages',
							report_def	=> 'mga_internal_users',
							sortby		=> 'internal_user'
							},
		incoming_mail_summary			=> {
							report_query	=> 'mga_overview_incoming_mail_summary',
							report_def	=> 'mga_overview',
							},
		incoming_mail_details			=> {
							report_query	=> 'mga_incoming_mail_domain_search',
							report_def	=> 'mga_incoming_mail',
							sortby		=> 'sender_domain'
							},
		average_time_in_workqueue		=> {
							report_query	=> 'mga_system_capacity_average_time_workqueue',
							report_def	=> 'mga_system_capacity',
							sortby		=> 'begin_timestamp'
							},
		);

sub new {
	my($class, %args) = @_;
	my $self = bless {}, $class;
        defined $args{server}   ? $self->{server}   = $args{server}   : croak 'Constructor failed: server not defined';
        defined $args{username} ? $self->{username} = $args{username} : croak 'Constructor failed: username not defined';
        defined $args{password} ? $self->{password} = $args{password} : croak 'Constructor failed: password not defined';
	$self->{proto}		= ($args{proto} or 'https');
	$self->{ua}		= LWP::UserAgent->new ( ssl_opts => { verify_hostname => 0 } );
	$self->{uri}		= $self->{proto}.'://'.$self->{username}.':'.$self->{password}.'@'.$self->{server}.'/monitor/reports/';
	return $self
}

{
	no strict 'refs';

	foreach my $m (keys %M_MAP) {
		*{ __PACKAGE__ . '::__' . $m } = sub {
			my ($self,%args) = @_;
			return $self->__request("report?format=csv&date_range=$args{date_range}&" .
						"report_query_id=$M_MAP{$m}{report_query}&" .
						"report_def_id=$M_MAP{$m}{report_def}")
		};

		foreach my $range (@RANGES) {
			my $p = ($m =~ /summary/ ? '__parse_summary' : '__parse_statistics');
			*{ __PACKAGE__ . '::' . $m . '_' . $range } = sub {
				my $self = shift;
				my $f = '__'.$m;
				return $p->($self->$f(date_range => $range), $M_MAP{$m}{sortby})
			};

			*{ __PACKAGE__ . '::' . $m . '_' . $range . '_raw' } = sub {
				my $self = shift;
				my $f = '__'.$m;
				return $self->$f(date_range => $range)
			};
		}
	}
}

sub __request {
        my($self,$uri)	= @_;
        my $res		= $self->{ua}->get($self->{uri}.$uri);
        $res->is_success and return $res->content;
        $self->{error}  = 'Unable to retrieve content: ' . $res->status_line;
        return 0
}

sub __parse_statistics {
	my ($d, $s)	= @_;
	my @d = split /\n/, $d;
	my %res;
	my @headers 	= map { s/ /_/g; s/\s*$//g; lc $_ } (split /,/, shift @d);
	my ($index)	= grep { $headers[$_] eq $s } 0..$#headers;
	
	foreach (@d) {
		my $c = 0;
		my @cols = split /,/;
		$cols[-1] =~ s/\s*$//;	

		foreach (@cols) {
			if (not defined $res{$cols[$index]}{$headers[$c]}) {
				$res{$cols[$index]}{$headers[$c]} = $_ 
			}
			elsif ( $headers[$c] =~ /end_(timestamp|date)/ ) { 
				$res{$cols[$index]}{$headers[$c]} = (sort { $b cmp $a } ($_, $res{$cols[$index]}{$headers[$c]}))[0] 
			}
			elsif ( $headers[$c] =~ /begin_(timestamp|date)/ ) {
				$res{$cols[$index]}{$headers[$c]} = (sort { $a cmp $b } ($_, $res{$cols[$index]}{$headers[$c]}))[0] 
			}
			elsif ( $headers[$c] =~ /(sender_domain|orig_value|internal_user)/ ) {
				$res{$cols[$index]}{$headers[$c]} = $_ 
			}
			else { 
				$res{$cols[$index]}{$headers[$c]} += $_ 
			}
			
			$c++
		}
	}

	return %res
}

sub __parse_summary {
	my $d = shift;
	my @d = split /\n/, $d;
	my %res;
	my @headers 	= map { s/ /_/g; s/\s*$//g; lc $_ } (split /,/, $d[0]);
	my @percent	= split /,/, $d[1]; $percent[-1] =~ s/\s*$//g;
	my @count	= split /,/, $d[2]; $count[-1] =~ s/\s*$//g;

	my $c = 0;
	foreach my $h (@headers) {
		$percent[$c] =~ s/--/100/;
		$res{$h}{'percent'}= $percent[$c];
		$res{$h}{'count'} = $count[$c];
		$c++
	}

	return %res
}

=head1 NAME

Cisco::IronPort - Interface to Cisco IronPort Reporting API

=head1 SYNOPSIS

	use Cisco::IronPort;

	my $ironport = Cisco::IronPort->new(
		username => $username,
		password => $password,
		server	 => $server
	);

	my %stats = $ironport->incoming_mail_summary_current_hour;

	print "Total Attempted Messages : $stats{total_attempted_messages}{count}\n";
	print "Clean Messages : $stats{clean_messages}{count} ($stats{clean_messages}{percent}%)\n";

	# prints...
	# Total Attempted Messages : 932784938
	# Clean Messages : (34%) 


=head1 METHODS

=head2 new ( %ARGS )

	my $ironport = Cisco::IronPort->new(
	  	username => $username,
	  	password => $password,
	  	server	 => $server
	);

Creates a Cisco::IronPort object.  The constructor accepts a hash containing three mandatory and one
optional parameter.

=over 3

=item username

The username of a user authorised to access the reporting API.

=item password

The password of the username used to access the reporting API.

=item server

The target IronPort device hosting the reporting API.  This value must be either a resolvable hostname
or an IP address.

=item proto

This optional parameter may be used to specify the protocol (either http or https) which should be used 
when connecting to the reporting API.  If unspecified this parameter defaults to https.

=back

=head2 incoming_mail_summary_current_hour

	my %stats = $ironport->incoming_mail_summary_current_hour;
	print "Total Attempted Messages : $stats{total_attempted_messages}{count}\n";

Returns a nested hash containing incoming mail summary statistics for the current hourly period.  The hash
has the structure show below:

	$stats = {
	  'statistic_name_1' =>	{
	    'count'   => $count,
	    'percent' => $percent
	  },
	  'statistic_name_2' => {
	    'count'   => $count,
	    'percent' => $percent
	  },
	  ...

	  'statistic_name_n => {
	    ...
	  }

Valid statistic names are show below - these names are derived from those returned by the reporting API
with all spaces converted to underscores and all characters lower-cased.

	stopped_by_reputation_filtering 
	stopped_as_invalid_recipients 
	stopped_by_content_filter 
	total_attempted_messages 
	total_threat_messages 
	clean_messages 
	virus_detected
	spam_detected 

=head2 incoming_mail_summary_current_day

Returns a nested hash with the same structure and information as described above for the B<incoming_mail_summary_current_hour>
method, but for a time period covering the current day.

=head2 incoming_mail_summary_current_hour_raw

Returns a scalar containing the incoming mail summary statistics for the current hour period unformated and as retrieved directly 
from the reporting API.

This method may be useful if you wish to process the raw data from the API call directly.

=head2 incoming_mail_summary_current_day_raw

Returns a scalar containing the incoming mail summary statistics for the current day period unformated and as retrieved directly 
from the reporting API.

This method may be useful if you wish to process the raw data from the API call directly.

=head2 incoming_mail_details_current_hour

	# Print a list of sending domains which have sent more than 50 messages
	# of which over 50% were detected as spam.

	my %stats = $ironport->incoming_mail_details_current_hour;
	
	foreach my $domain (keys %stats) {
	  if ( ( $stats{$domain}{total_attempted} > 50 ) and 
	       ( int (($stats{$domain}{spam_detected}/$stats{$domain}{total_attempted})*100) > 50 ) {
	    print "Domain $domain sent $stats{$domain}{total_attempted} messages, $stats{$domain}{spam_detected} were marked as spam.\n"
	  }
	}

Returns a nested hash containing details of incoming mail statistics for the current hour period.  The hash has the following structure:

	sending.domain1.com => {
	  begin_date				=> a human-readable timestamp at the beginning of the measurement interval (YYYY-MM-DD HH:MM TZ),
	  begin_timestamp			=> seconds since epoch at the beginning of the measurement interval (resolution of 100ms),
	  clean					=> total number of clean messages sent by this domain,
	  connections_accepted			=> total number of connections accepted from this domain,
	  end_date				=> a human-readable timestamp at the end of the measurement interval (YYYY-MM-DD HH:MM TZ),
	  end_timestamp				=> seconds since epoch at the end of the measurement interval (resolution of 100ms),
	  orig_value				=> the domain name originally establishing the connection prior to any relaying or masquerading,
	  sender_domain				=> the sending domain,
	  spam_detected				=> the number of messages marked as spam from this domain,
	  stopped_as_invalid_recipients		=> number of messages stopped from this domain due to invalid recipients,
	  stopped_by_content_filter		=> number of messages stopped from this domain due to content filtering,
	  stopped_by_recipient_throttling	=> number of messages stopped from this domain due to recipient throttling,
	  stopped_by_reputation_filtering	=> number of messages stopped from this domain due to reputation filtering,
	  total_attempted			=> total number of messages sent from this domain,
	  total_threat				=> total number of messages marked as threat messages from this domain,
	  virus_detected			=> total number of messages marked as virus positive from this domain
	},
	sending.domain2.com => {
	  ...
	},
	...
	sending.domainN.com => {
	  ...
	}

Where each domain having sent email in the current hour period is used as the value of a hash key in the returned hash having
the subkeys listed above.  For a busy device this hash may contain hundreds or thousands of domains so caution should be 
excercised in storing and parsing this structure.

=head2 incoming_mail_details_current_day

This method returns a nested hash as described in the B<incoming_mail_details_current_hour> method above but for a period
of the current day.  Consequently the returned hash may contain a far larger number of entries.

=head2 incoming_mail_details_current_hour_raw

Returns a scalar containing the incoming mail details for the current hour period as retrieved directly from the reporting
API.  This method is useful is you wish to access and/or parse the results directly.

=head2 incoming_mail_details_current_day_raw

Returns a scalar containing the incoming mail details for the current day period as retrieved directly from the reporting
API.  This method is useful is you wish to access and/or parse the results directly.

=head2 top_users_by_clean_outgoing_messages_current_hour

	# Print a list of our top internal users and number of messages sent.
	
	my %top_users = $ironport->top_users_by_clean_outgoing_messages_current_hour;

	foreach my $user (sort keys %top_users) {
	  print "$user - $top_users{clean_messages} messages\n";
	}

Returns a nested hash containing details of the top ten internal users by number of clean outgoing messages sent for the
current hour period.  The hash has the following structure:

	'user1@domain.com' => {
	  begin_date		=> a human-readable timestamp of the begining of the current hour period ('YYYY-MM-DD HH:MM TZ'),
	  begin_timestamp	=> a timestamp of the beginning of the current hour period in seconds since epoch,
	  end_date		=> a human-readable timestamp of the end of the current hour period ('YYYY-MM-DD HH:MM TZ'),
	  end_timestamp		=> a timestamp of the end of the current hour period in seconds since epoch,
	  internal_user		=> the email address of the user (this may also be 'unknown user' if the address cannot be determined),
	  clean_messages	=> the number of clean messages sent by this user for the current hour period
	},
	'user2@domain.com' => {
	  ...
	},
	...
	user10@domain.com' => {
	  ...
	}

=head2 top_users_by_clean_outgoing_messages_current_day

Returns a nested hash containing details of the top ten internal users by number of clean outgoing messages sent for the
current day period.

=head2 top_users_by_clean_outgoing_messages_current_hour_raw

Returns a scalar containing the details of the top ten internal users by number of clean outgoing messages sent for the
current hour period as retrieved directly from the reporting API.  

This method may be useful if you wish to process the raw data retrieved from the API yourself.

=head2 top_users_by_clean_outgoing_messages_current_day_raw

Returns a scalar containing the details of the top ten internal users by number of clean outgoing messages sent for the
current day period as retrieved directly from the reporting API.  

This method may be useful if you wish to process the raw data retrieved from the API yourself.

=head2 average_time_in_workqueue_current_hour

	my %stats = $ironport->average_time_in_workqueue_current_day;
	
	foreach my $i (sort keys %stats) {
		print "$stats{$i}{end_date} : $stats{$i}{time}\n"
	}
	
	# Prints the average time a message spent in the workqueue for the current hourly period
	# e.g.
	# 2012-08-07 03:34 GMT : 1.76650943396
	# 2012-08-07 03:39 GMT : 4.97411003236
	# 2012-08-07 03:44 GMT : 0.955434782609
	# 2012-08-07 03:49 GMT : 3.38574040219
	# 2012-08-07 03:54 GMT : 2.32837301587
	# ...

This method returns a nested hash containing statistics for the average time a message spent in the workqueue for
the previous hourly period - the hash has the following structure:

	measurement_period_1_begin_timestamp => {
	  begin_timestamp	=> a timestamp marking the beginning of the measurement period in seconds since epoch,
	  end_timestamp		=> a timestamp marking the ending of the measurement period in seconds since epoch,
	  begin_date		=> a human-readable timestamp marking the beginning of the measurement period (YYYY-MM-DD HH:MM:SS TZ),
	  end_date		=> a human-readable timestamp marking the ending of the measurement period (YYYY-MM-DD HH:MM:SS TZ),
	  time			=> the average time in seconds a message spent in the workqueue for the measurement period
	},
	measurement_period_2_begin_timestamp => {
	  ...
	},
	...
	measurement_period_n_begin_timestamp => {
	  ...
	}

=head2 average_time_in_workqueue_current_day

Returns a nested hash containing statistics for the average time a message spent in the workqueue for the previous
daily period - the hash has the same structure as detailed in the B<average_time_in_workqueue_current_hour> above.

=head2 average_time_in_workqueue_current_hour_raw

Returns a scalar containing statistics for the average time a message spent in the workqueue for the previous hourly
period as retrieved directly from the reporting API.

This method may be useful if you wish to process the raw data retrieved from the API yourself.

=head2 average_time_in_workqueue_current_day_raw

Returns a scalar containing statistics for the average time a message spent in the workqueue for the previous daily
period as retrieved directly from the reporting API.

This method may be useful if you wish to process the raw data retrieved from the API yourself.

=cut

=head1 AUTHOR

Luke Poskitt, C<< <ltp at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-cisco-ironport at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Cisco-IronPort>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Cisco::IronPort


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Cisco-IronPort>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Cisco-IronPort>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Cisco-IronPort>

=item * Search CPAN

L<http://search.cpan.org/dist/Cisco-IronPort/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Luke Poskitt.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Cisco::IronPort
