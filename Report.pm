package  Ska::GuideStats::Report;

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;

use Chandra::Time;
use IO::All;

use Carp;
use Ska::SQL::Select;
use YAML;
use Ska::DatabaseUtil qw( sql_connect );

use Math::CDF;

use Date::Format;
use Date::Tie;
use File::Path qw( mkpath rmtree );

use PDL;
use PDL::NiceSlice;
use PGPLOT::Simple qw( pgs_plot );

use Ska::Run;

my $task = 'guide_stat_reports';
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $SHARE = "${SKA}/share/guide_stat_reports";
my $WEBDATA = "${SKA}/www/ASPECT/${task}";
my $SKADATA = "${SKA}/data/${task}";
my $BASEURL = "http://cxc.harvard.edu/mta/ASPECT/${task}";
    

sub standard_report{

    my $arg_in = shift;
    my %config = %{$arg_in->{config}};
    my %opt = %{$arg_in->{opt}};

    eval{
	calc_report({ config => \%config,
		      opt => \%opt,
		  });

    };
    if($@){
	if ("$@" =~ /No stars/){
	    print "No Stars during this interval \n";
	}
    }
    else{

	make_plots({ config => \%config,
		     opt => \%opt,
		 });
	
	
    }
}
    


sub calc_report{


    my $arg_in = shift;
    my %config = %{$arg_in->{config}};
    my %opt = %{$arg_in->{opt}};

# create a hash to store the bits that end up in the report
    my %report;


    my %mission_interval = %{define_interval({ tstart => $opt{calc_rate_tstart},
					       tstop => $opt{calc_rate_tstop}}) };
    
    my %report_interval = %{define_interval({ tstart => $opt{tstart},
					      tstop => $opt{tstop} })};


    my %counts = %{get_counts({ mission_interval => \%mission_interval,
				report_interval => \%report_interval,
				config => \%config,
				mag_zoom => $config{task}->{data}->{mag_zoom},
			    })};
	    
    #if there aren't any stars, let's stop fooling around
    if ($counts{report}->{all_stars} == 0){
	croak("No stars during this interval");
    }


    my %expected = %{calc_expected({ mission => $counts{mission},
				     actual => $counts{report},
				     config => \%config })};
    $expected{name} = 'expected';

    $counts{expected} = \%expected;

    my %prob = %{calc_prob({ expected => \%expected,
			     actual => $counts{report},
			     config => \%config })};
    
    for my $key (keys %prob){
	$counts{report}->{$key} = $prob{$key};
    }

    make_top_table({ 
	
	report => \%report,
	expected => $counts{expected},
	actual => $counts{report},
	config => \%config,
	opt => \%opt});
    
#    print $toptable;

    make_mag_table({ 
	report => \%report,
	data => \%counts,
	config => \%config,
	opt => \%opt});


#    print $mag_table;

#    use Data::Dumper;

#    print Dumper %counts;

#
    my $ctime_start = Chandra::Time->new( $report_interval{tstart} );
    my $ctime_stop = Chandra::Time->new( $report_interval{tstop} );
    $report{DATE_START} = $ctime_start->date();
    $report{DATE_STOP} = $ctime_stop->date();
    
    
    $report{HUMAN_DATE_START} = time2str("%d-%b-%Y", $ctime_start->unix(), '+0000');
    $report{HUMAN_DATE_STOP} =  time2str("%d-%b-%Y", $ctime_stop->unix(), '+0000' );

    $report{DATA} = \%counts;

#
#    }

    my $url = '.';
    if (defined $opt{predefined}){
	$url = $BASEURL . "/" . $opt{year} . "/" . $opt{id};
    }


    for my $plot (keys %{$config{task}->{plots}}){
	$report{uc($plot) . "_PLOT"} = qq{<IMG SRC="${url}/$config{task}->{plots}->{$plot}->{plot_name}">};
    }

    $report{TITLE} = qq{};
    if (defined $opt{title}){
	$report{TITLE} = $opt{title};
    }

    make_report({ config => \%config,
		  report_hash => \%report,
		  opt => \%opt,
	      });

}

sub make_mag_table{
    my $arg_in = shift;
    my $report = $arg_in->{report};
    my $config = $arg_in->{config};
    my $data = $arg_in->{data};
    my %opt = %{$arg_in->{opt}};
    
    my @fields = qw( all_stars );
    for my $rate ( sort( keys %{$config->{task}->{data}->{rates}} )){
	push @fields, "${rate}_stars";
  	push @fields, "${rate}_rate";
    }
    

    my $table;

    $table .= "\n";
    $table .= qq{ <TABLE BORDER=1> };
    $table .= "\n"; 

    $table .= qq{ <TR><TH colspan=2></TH><TH colspan=2>Bad Track</TH> };
    $table .= qq{ <TH colspan=2>Fail Track</TH> };
    $table .= qq{ <TH colspan=2>OBC Bad Status</TH></TR> \n };

    $table .= qq{ <TR><TH>Mag</TH><TH>N Stars</TH> };
    $table .= qq{ <TH colspan=1>stars</TH> };
    $table .= qq{ <TH colspan=1>rate</TH> };
    $table .= qq{ <TH colspan=1>stars</TH> };
    $table .= qq{ <TH colspan=1>rate</TH> };
    $table .= qq{ <TH colspan=1>stars</TH> };
    $table .= qq{ <TH colspan=1>rate</TH> };
    $table .= qq{ </TR> \n };


#    $table .= qq{ <TR><TH></TH><TH>n stars</TH> };
#    $table .= qq{ <TH>actual</TH><TH>pred.</TH><TH>P less</TH><TH>P more</TH> };
#    $table .= qq{ <TH>actual</TH><TH>pred.</TH> };
#    $table .= qq{ <TH>actual</TH><TH>pred.</TH><TH>P less</TH><TH>P more</TH> };
#    $table .= qq{ <TH>actual</TH><TH>pred.</TH> };
#    $table .= qq{ <TH>actual</TH><TH>pred.</TH><TH>P less</TH><TH>P more</TH> };
#    $table .= qq{ <TH>actual</TH><TH>pred.</TH> };
#    $table .= qq{ </TR> \n };
#

#    $table .= qq{ <TH></TH> };

    

#    for my $field (@fields){
#	$table .= qq{ <TH>$field</TH> };
#    }
#    $table .= "\n";

    



    for my $mag_bin ( sort( keys %{$data->{report}->{mag_bins}}) ){

	my $dataref = $data->{report}->{mag_bins}->{$mag_bin};
#	print "mag bin is $mag_bin \n";
	$table .= qq{ <TR> };

	$table .= qq{ <TD>$mag_bin - $dataref->{mag_stop} </TD> };
	
#	my %expected = %{calc_expected({ mission => $data->{mission}->{mag_bins}->{$mag_bin},
#					 actual => $data->{report}->{mag_bins}->{$mag_bin},
#					 config => $config })};

#	for my $key (keys %expected){
#	    $data->{report}->{mag_bins}->{$mag_bin}->{$key} = $expected{$key};
#	}
#	$data->{report}->{mag_bins}->{$mag_bin}->{expected} = \%expected;

#	my %prob = %{calc_prob({ expected => \%expected,
#				 actual => $data->{report}->{mag_bins}->{$mag_bin},
#				 config => $config })};
	
	
#	for my $key (keys %prob){
#	    $data->{report}->{mag_bins}->{$mag_bin}->{$key} = $prob{$key};
#	}


	
	for my $field (@fields){

	    my $table_value;
#	    print "$interval field is $field \n";
	    if (defined $dataref->{$field}){
		$table_value = $dataref->{$field};
		my $format_value;
		if ($field ne 'all_stars' and $field =~ /stars$/ and $table_value > 0){
#		    print ref($dataref->{sql_where}), "\n";
		    my $table_field = $field;
		    $table_field =~ s/_stars$// ;
		    my $star_table = make_star_table({ where => $dataref->{sql_where},
						       field => $table_field,
						       config => $config  });
		    $mag_bin =~ s/\./p/;	
		    my $url = '.';
		    if (defined $opt{predefined}){
			$url = $BASEURL . "/" . $opt{year} . "/" . $opt{id};
		    }
	    
		    my $link = "${url}/" . lc($field) . "_${mag_bin}_list.html";
		    my $hashname = uc($field) . "_${mag_bin}_LIST";
#		    print "for $mag_bin field $field \n";
#		    print "$hashname \n";
#		    print "$link \n";
		    $report->{$hashname} = $star_table;
		    $format_value = "<A HREF=\"${link}\">${table_value}</A>";
		}
		else{
#		print "$table_value \n";
		    if ($table_value =~ /^\S*$/){
			$format_value = $table_value;
		    }

		    if ($table_value =~ /^\d*$/ ){
			$format_value = $table_value;
		    }
		    if ($table_value =~ /^\d*\.\d*$/ ){
			$format_value = sprintf( "%6.4f", $table_value );
		    }
		}
		if (defined $format_value ){
		    $table .= qq{ <TD> $format_value </TD> };
		}
		else{
		    $table .= qq{ <TD> </TD> };
		    
		}
	    }
	    else{
		$table .= qq{ <TD> </TD> };
	    }
	}
	
	
	$table .= qq{ </TR> \n };

    }

    $table .= qq{ </TABLE> };

    $report->{MAG_TABLE} = $table;

}

sub make_star_table{
    my $arg_in = shift;
    my %where = %{$arg_in->{where}};
    my $field;
    if (defined $arg_in->{field}){
	$field = $arg_in->{field};
    }
    my %config = %{$arg_in->{config}};


    my $select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
					 fields => [ 'id', 'obsid', 'mag_exp', 'mag_obs_mean',
						     'percent_not_tracking', 'percent_obc_bad_status' ],
					 where => \%where,
					 order => [ 'kalman_tstart' ],
				     });

    if (defined $field){
	my %make_select = %{$config{task}->{data}->{rates}->{$field}};
	    
	$select->add_where({ $make_select{field} => { $make_select{operator} => $make_select{value} }});
	
    }
    
    my $handle = sql_connect( $config{task}->{db}->{connect_info} );

    my $answer_list = $select->run({ handle => $handle, type => 'array' });

    $handle->disconnect();

#    print Dumper $answer_list;

    my $list = qq{};
#    $list = $select->get_select_string();

#    my @bad_star_list;
    if (scalar(@{$answer_list})){
	$list .= qq{<TABLE BORDER=1>};
	$list .= qq{<TR><TH>count</TH><TH>agasc_id</TH><TH>obsid</TH><TH>mag</TH><TH>mag_obs_mean</TH><TH>% not tracking</TH><TH>% obc bad status</TH></TR>};
	my @key_list = qw( mag_exp mag_obs_mean percent_not_tracking percent_obc_bad_status);
	my @format_list = ( '%5.2f', '%5.2f', '%4.2f', '%4.2f' );
	my $count = 1;
	for my $starref (@{$answer_list}){
	    if ($count > $config{task}->{limit_bad_list}){
		$list .= "<TR><TD COLSPAN=7> Stars excluded over limit </TD></TR>\n";
		last;
	    }
	    $list .= sprintf("<TR><TD ALIGN=\"right\">%d</TD>", $count );
	    my $id = ( defined $starref->{id} ) ? $starref->{id} : qq{};
	    $list .= sprintf("<TD ALIGN=\"right\"><A HREF=\"%s\?id=%s;\">%12s</A></TD>", 
			     $config{task}->{stats_print}, $id, $id);
	    $list .= sprintf("<TD ALIGN=\"right\"><A HREF=\"%s\?sselect=obsid\;obsid1=%d\">%d</A></TD>", 
			     $config{task}->{starcheck_print}, $starref->{obsid}, $starref->{obsid}); 
	    for my $key_idx (0 ... $#key_list){
		my $key = $key_list[$key_idx];
		my $format = $format_list[$key_idx];
		if (not defined $starref->{$key}){
		    $list .= qq{ <TD></TD> };
		}
		else{
		    $list .= sprintf("<TD ALIGN=\"right\">$format</TD>", $starref->{$key});
		}


	    }
#	    $list .=  sprintf( "<TR><TD ALIGN=\"right\">%d</TD><TD ALIGN=\"right\">%12s</TD><TD ALIGN=\"right\">%5s</TD><TD ALIGN=\"right\">%5.2f</TD><TD ALIGN=\"right\">%5.2f</TD><TD ALIGN=\"right\">%4.2f</TD><TD ALIGN=\"right\">%6.2f</TD></TR>", 
#			       $count, $star{id}, $star{obsid}, $star{mag_exp}, $star{mag_obs_mean}, 
#			       $star{percent_not_tracking}, $star{percent_obc_bad_status} );


	    $count++;	    
	}
	
    }

#    print $list, "\n";
    return $list;
}



    

sub calc_prob{
    my $arg_in = shift;

    my $config = $arg_in->{config};
    my $actual = $arg_in->{actual};
    my $expected = $arg_in->{expected};
#    print "actual";
#2#B    print Dumper $actual;
 #   print "expected";
 #   print Dumper $expected;

    my %prob;

    for my $rate ( sort( keys %{$config->{task}->{data}->{rates}} )){
#        print "rate is $rate \n";
	my $expected_counts = $expected->{"${rate}_stars"};
	my $actual_counts = $actual->{"${rate}_stars"};
	my $lt_or_eq_prob = Math::CDF::ppois( $actual_counts, $expected_counts );
	my $gt_or_eq_prob;
	if ( $actual_counts > 0 ){
#	    print "expected:$expected_counts actual:$actual_counts \n";
	    $gt_or_eq_prob = 1 - Math::CDF::ppois( $actual_counts - 1, $expected_counts );
#	    print ":", Math::CDF::ppois( $actual_counts - 1, $expected_counts ), ":\n";
	}
	else{
	    $gt_or_eq_prob = 1;
	}
	$prob{"${rate}_pless"} = $lt_or_eq_prob;
	$prob{"${rate}_pmore"} = $gt_or_eq_prob;
    }

    return \%prob;
}


sub calc_expected{
    my $arg_in = shift;
    my $config = $arg_in->{config};
    my $mission = $arg_in->{mission};
    my $actual = $arg_in->{actual};

 #   print Dumper $mission;
 #   print Dumper $actual;

    my %expected;

    my $n_stars = $actual->{all_stars};

    for my $rate ( sort( keys %{$config->{task}->{data}->{rates}} )){
	if (defined $mission->{"${rate}_rate"}){
	    $expected{"${rate}_rate"} = $mission->{"${rate}_rate"};
	    $expected{"${rate}_stars"} = $n_stars * $mission->{"${rate}_rate"};
	}
    }
#    print Dumper %expected;

    return \%expected;

}

sub make_top_table{

    my $arg_in = shift;
    my $report = $arg_in->{report};
    my $config = $arg_in->{config};
    my $expected = $arg_in->{expected};
    my $actual = $arg_in->{actual};
    my %opt = %{$arg_in->{opt}};

#    my @data = ( $expected , $actual );
#    print Dumper @data;

    my $table = qq{ <TABLE BORDER=1>\n };
    
    my @fields = qw( name all_stars );
    my @colspan = qw( 1 1 );
    for my $rate ( sort( keys %{$config->{task}->{data}->{rates}} )){
	push @fields, "${rate}_stars";
	push @colspan, 4;
  	push @fields, "${rate}_rate";
	push @colspan, 2;
    }
 #   print Dumper @fields;
#    $table .= qq{ <TH></TH> };
 
#    for my $field (@fields){
#	$table .= qq{ <TH>$field</TH> };
#    }
    $table .= qq{ <TR><TH colspan=2></TH><TH colspan=6>Bad Track</TH> };
    $table .= qq{ <TH colspan=6>Fail Track</TH> };
    $table .= qq{ <TH colspan=6>OBC Bad Status</TH></TR> \n };

    $table .= qq{ <TR><TH></TH><TH></TH> };
    $table .= qq{ <TH colspan=4>stars</TH> };
    $table .= qq{ <TH colspan=2>rate</TH> };
    $table .= qq{ <TH colspan=4>stars</TH> };
    $table .= qq{ <TH colspan=2>rate</TH> };
    $table .= qq{ <TH colspan=4>stars</TH> };
    $table .= qq{ <TH colspan=2>rate</TH> };
    $table .= qq{ </TR> \n };


    $table .= qq{ <TR><TH></TH><TH>n stars</TH> };
    $table .= qq{ <TH>actual</TH><TH>pred.</TH><TH>P less</TH><TH>P more</TH> };
    $table .= qq{ <TH>actual</TH><TH>pred.</TH> };
    $table .= qq{ <TH>actual</TH><TH>pred.</TH><TH>P less</TH><TH>P more</TH> };
    $table .= qq{ <TH>actual</TH><TH>pred.</TH> };
    $table .= qq{ <TH>actual</TH><TH>pred.</TH><TH>P less</TH><TH>P more</TH> };
    $table .= qq{ <TH>actual</TH><TH>pred.</TH> };
    $table .= qq{ </TR> \n };

    
    $table .= "\n";

 #   for my $dataref (@data){

    $table .= qq{ <TR> };
  FIELD:
    for my $field_idx (0 ... $#fields){
	my $field = $fields[$field_idx];
	my $cols = $colspan[$field_idx];
	unless (defined $actual->{$field}){
	    $table .= qq{ <TD colspan=$cols></TD> };
	    next FIELD;
	}
	my $table_value = $actual->{$field};
	if ($field ne 'all_stars' and $field =~ /stars$/ and $table_value > 0 and defined $actual->{sql_where}){
#		    print ref($dataref->{sql_where}), "\n";
	    my $table_field = $field;
	    $table_field =~ s/_stars$//;
	    my $star_table = make_star_table({ where => $actual->{sql_where},
					       field => $table_field,
					       config => $config  });
	    my $url = '.';
	    if (defined $opt{predefined}){
		$url = $BASEURL . "/" . $opt{year} . "/" . $opt{id};
	    }
	    my $link = "${url}/" . lc($field) . "_list.html";
	    my $list_key = uc($field) . "_LIST";
	    $report->{$list_key} = $star_table;
	    $table .= sprintf("<TD><A HREF=\"%s\">%d</A></TD><TD>%6.1f</TD><TD>%6.3f</TD><TD>%6.3f</TD>",
			       $link, $table_value, $expected->{$field}, 
			       $actual->{"${table_field}_pless"}, $actual->{"${table_field}_pmore"}) ;
	    next FIELD;
	}
	if ($field ne 'all_stars' and $field =~ /stars$/ and $table_value == 0){
	    my $table_field = $field;
	    $table_field =~ s/_stars$//;
	    $table .= sprintf("<TD>%d</TD><TD>%6.1f</TD><TD>%6.3f</TD><TD>%6.3f</TD>",
			       $table_value, $expected->{$field}, 
			       $actual->{"${table_field}_pless"}, $actual->{"${table_field}_pmore"}) ;
	    next FIELD;
	}	    
	if ($field =~ /_rate$/){
	    $table  .= sprintf("<TD>%6.3f</TD><TD>%6.3f</TD>", $table_value, $expected->{$field});
	    next FIELD;
	}
	if ($table_value =~ /^\d+$/ ){
	    $table .= qq{ <TD>$table_value</TD> };
	    next FIELD;
	}
	if ($table_value =~ /^\d+\.\d+$/ ){
	    $table .=  sprintf( "<TD>%6.4f</TD>", $table_value );
	    next FIELD;
	}
	if ($table_value =~ /^\S*$/){
	    $table .= sprintf( "<TD>%s</TD>", $table_value );
	    next FIELD;
	}

    }
    $table .= qq{ </TR> \n };
    
#    $table .= qq{ <TR> };
    
#    for my $field (@fields ){
##	print Dumper $data->{report};
#	$field =~ s/_stars//g;
##	print "$field \n";
#	if (defined $actual->{"${field}_pless"}){
##	    print $data->{report}->{"${field}_pless"}, "\n";
#	    $table .= sprintf( "<TD>%6.4f</TD>" ,  $actual->{"${field}_pless"});
#	}
#	else{
#	    $table .= qq{ <TD> </TD> };
#	}
#    }
#    $table .= qq{ </TR> \n };
#    $table .= qq{ <TR> };
#    for my $field (@fields ){
#	$field =~ s/_stars//g;
#	if (defined $actual->{"${field}_pmore"}){
#	    $table .= sprintf( "<TD>%6.4f</TD>" ,  $actual->{"${field}_pmore"});
#	}
#	else{
#	    $table .= qq{ <TD> </TD> };
#	}
#    }
#    $table .= qq{ </TR> \n };
    

    $table .= "\n";
    $table .= qq{ </TABLE> };
    $table .= "\n"; 

    $report->{MAIN_TABLE} = $table;


}
    


sub make_report_hash{
    my $arg_in = shift;
    
    my %report_hash;

    my $mission_rate = $arg_in->{mission_rate};
    my $interval_rate = $arg_in->{interval_rate};
    my %config = %{$arg_in->{config}};

    $report_hash{N_STARS} = $interval_rate->{all};
    $report_hash{N_BAD_STARS} = $interval_rate->{bad};
    $report_hash{N_FAIL_STARS} = $interval_rate->{total_fail};
    $report_hash{FAIL_RATE} = sprintf( "%6.2f", ($interval_rate->{total_fail}/$interval_rate->{all}) * 100);
    $report_hash{BAD_RATE} = sprintf( "%6.2f", ($interval_rate->{bad}/$interval_rate->{all}) * 100 );

    my $expected_rate = $mission_rate->{bad}/$mission_rate->{all};
    
    $report_hash{EXP_BAD_RATE} = sprintf( "%6.2f", $expected_rate * 100);
    $report_hash{EXP_FAIL_RATE} = sprintf( "%6.2f", ($mission_rate->{total_fail}/$mission_rate->{all}) * 100);
    
    my $expected_counts = $interval_rate->{all} * $expected_rate;
    
    $report_hash{EXP_N} = sprintf( "%6.2f", $expected_counts);
    $report_hash{EXP_N_FAIL} = sprintf( "%6.2f", ($interval_rate->{all} * ($mission_rate->{total_fail}/$mission_rate->{all})));
    
    my $lt_or_eq_prob = Math::CDF::ppois( $interval_rate->{bad}, $expected_counts );

    $report_hash{PROB_N_LESS} = sprintf( "%6.4f", $lt_or_eq_prob);
    
# the greater than probability seems to break on 0 counts, so:
    my $gt_or_eq_prob;
    if ( $interval_rate->{bad} > 0 ){
	$gt_or_eq_prob = 1 - Math::CDF::ppois( $interval_rate->{bad} - 1, $expected_counts );
    }
    else{
	$gt_or_eq_prob = 1;
    }
    
    $report_hash{PROB_N_MORE} = sprintf( "%6.4f", $gt_or_eq_prob);
    
    return \%report_hash;
}    

#sub ctime_to_datetie{
#    my $ctime = shift;
#    my $fitsdate = Chandra::Time::convert($time,
#					  { fmt_in => 'secs',
#					    sys_in => 'tt',
#					    fmt_out => 'fits',
#					    sys_out => 'utc',
#					});
#    $fitsdate =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})/;
#    my ($year, $month, $monthday, $hour, $min, $sec, $fracsec) = ( $1, $2, $3, $4, $5, $6, $7);
#    my $datetie = Date::Tie->new( year => $year,
#				  month => $month,
#				  monthday => $monthday,
#				  hour => $hour,
#				  minute => $min,
#				  second => $sec,
#				  frac_second => $fracsec );
#    return $datetie;
#}

sub date_to_fits_format{

    my $time_ref = shift;

    my @pieces = ( 'year', 'month', 'monthday', 'hour', 'minute', 'second' );
    for my $part (@pieces){
	unless ( defined $time_ref->{$part}){
	    die "$part not defined for time\n";
	}
    }
    my $fits_string = sprintf("%4d-%02d-%02dT%02d:%02d:%02d.000",
			      $time_ref->{year}, $time_ref->{month},
			      $time_ref->{monthday}, $time_ref->{hour},
			      $time_ref->{minute}, $time_ref->{second});

    return $fits_string;


}

sub date_to_doy_format{
    my $time_ref = shift;

    my @pieces = ( 'year', 'yearday', 'hour', 'minute', 'second' );
    for my $part (@pieces){
	unless ( defined $time_ref->{$part}){
	    die "$part not defined for time\n";
	}
    }
    my $doy_string = sprintf("%4d:%03d:%02d:%02d:%02d.000",
			      $time_ref->{year}, $time_ref->{yearday},
			      $time_ref->{hour},
			      $time_ref->{minute}, $time_ref->{second});

    return $doy_string;

}



sub make_report{


    my $arg_in = shift;
    my $config = $arg_in->{config};
    my %report = %{$arg_in->{report_hash}};
    my $opt = $arg_in->{opt};

#    my $template_file = "${SHARE}/" . $report_config->{report_text};
#    my $template_file = "${SHARE}/" . $config->{task}->{template_file};
#    my $template_file = $config->{task}->{template_file};
#    my $report_text = io($template_file)->slurp;

    my @lists;
    my @tables;
#    print Dumper %report;
    for my $keyword (keys %report){
	if ( $keyword =~ /^.*LIST$/){
	    push @lists, $keyword;
	    next;
	}
	if ( $keyword =~ /^.*TABLE$/){
	    push @tables, $keyword;
	    next;
	}
#	my $file_keyword = uc($keyword);
#	if (ref($report{$keyword}) eq 'ARRAY'){
#	    my $text = '';
#	    for my $line (@{$report{$keyword}}){
#		$text .= "$line \n";
#	    }
#	    $report_text =~ s/%${file_keyword}%/$text/g;
#	}
#	else{
#	    $report_text =~ s/%${file_keyword}%/$report{$keyword}/g;
#	}
    }
#    print Dumper @lists;


#    my $destfile = $config->{task}->{report_file};
    my $yamlfile = $config->{task}->{report_yaml_file};

    my $save_prefix = qq{};
    my $data_save_prefix;
#    if (defined $opt->{save_string}){
#	$save_prefix = $opt->{save_string};
#    }
 

    if (defined $opt->{save_path}){
	if (defined $opt->{predefined}){
#	    print "current save is ", $opt->{save_path}, "\n";
	    $save_prefix = $WEBDATA . "/" . $opt->{save_path} . "/";
	    $data_save_prefix = $SKADATA . "/" . $opt->{save_path} . "/";
	    # watch the order here... don't extend save_path before data_save_path
	    $opt->{data_save_path} = $SKADATA . "/" . $opt->{save_path};
	    $opt->{save_path} = $WEBDATA . "/" . $opt->{save_path};

	}
	else{
	    $save_prefix = $opt->{save_path} . "/";
	}
    }

    if (not defined $data_save_prefix){
	$data_save_prefix = $save_prefix;
    }

#    use Data::Dumper;
#    print Dumper $opt;


#    print "destfile is $destfile \n";
    unless ($opt->{dryrun}){
	print "in writing section \n;";

	if (defined $opt->{save_path}){
	    mkpath( $opt->{save_path}, 1 );
	}
	if (defined $opt->{data_save_path}){
	    mkpath( $opt->{data_save_path}, 1);
	}
	
	my $index_infile = $config->{task}->{index_file};
	if ($opt->{predefined}){
	    $index_infile = $config->{task}->{predefined_index_file};
	}
	
	if (-e "${SHARE}/${index_infile}"){
	    my $index = io("${SHARE}/${index_infile}")->slurp;
	    io("${save_prefix}/index.html")->print($index);
	}
#	print "${save_prefix}${destfile} \n";
#	io("${save_prefix}${destfile}")->print($report_text);

	for my $list (@lists){
	    my $file = lc($list);
	    io("${save_prefix}${file}.html")->print($report{$list});
	    # and remove the lists from the report hash
	    delete $report{$list};
	}
	# let's manually clear the tables so they don't ugly-up the yaml
	for my $table (@tables){
	    my $file = lc($table);
	    io("${save_prefix}${file}.htm")->print($report{$table});
	    delete $report{$table};
	}

	if (defined $yamlfile){
	    io("${data_save_prefix}${yamlfile}")->print(Dump(\%report));
	}
	
	#let's write out everything that is left except the DATA
	for my $key (keys %report){
	    unless ($key eq 'DATA' ){
		my $file = lc($key);
		io("${save_prefix}${file}.htm")->print($report{$key});
	    }
	}

    }
    else{
	print "ran dryrun \n";
    }
    

}





sub define_interval{

    my $time_hash_ref = shift;
    my %interval;

    for my $time_key (keys %{$time_hash_ref}){
	my $time = $time_hash_ref->{$time_key};
	my $time_obj;

	eval{
	    # if a fits format, override default time system of tt
	    if ($time =~ /^\d{4}-\d{1,2}-\d{1,2}T\d{1,2}:\d{1,2}:\d{1,2}(\.\d*)?$/ ){
		# my use of the fits date type was just because it was pretty
		# not because I really wanted to use the default TT system for FITS
		# so, I'm doing the conversion manually
		$interval{$time_key} = Chandra::Time::convert($time,
							      { fmt_in => 'fits',
								sys_in => 'utc',
								fmt_out => 'secs',
								sys_out => 'tt',
							    });
	    }
	    else{
		$interval{$time_key} = Chandra::Time->new($time)->secs();
	    }
	    
	};
	if ($@){
	    croak("Could not parse $time_key using Chandra::Time \n");
	}
	
    }
    return \%interval;

}


sub bad_track_rate{

    my $arg_in = shift;
    my %interval = %{$arg_in->{interval}};
    my %config = %{$arg_in->{config}};
   
    my $BAD_PERCENT = $config{task}->{bad_telem_threshold};

    my $handle = sql_connect( $config{task}->{db}->{connect_info} );

    my $exclude_bad_obsid = 'not in (select obsid from expected_bad_obsids)';
    my $select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
					 fields => [ "count(id) as n" ],
					 where => { 
					     obsid => \$exclude_bad_obsid,      
					     type => { '!=' => 'FID'},
					     id => { '!=' => '---' },
					     kalman_tstart => { '>=' => $interval{tstart} },
					     kalman_tstop => { '<=' => $interval{tstop} },
					 },					       
				     });
    

#    print $select->get_select_string(), "\n";
    my $count_all_ref =  $select->run({handle => $handle, type => 'array' });
    my $count_all = $count_all_ref->[0]->{n};

    $select->add_where({ 'percent_not_tracking' => { '>=' => $BAD_PERCENT }});

#    print $select->get_select_string(), "\n";

    my $count_bad_ref = $select->run({handle => $handle, type => 'array' });
    my $count_bad = $count_bad_ref->[0]->{n};

    # total failures
    $select->add_where({ 'percent_not_tracking' => 100 });

    my $count_fail_ref = $select->run({handle => $handle, type => 'array' });
    my $count_fail = $count_fail_ref->[0]->{n};



    $handle->disconnect();

    my %result = ( bad => $count_bad,
		   all => $count_all,
		   total_fail => $count_fail,
		   tstart => $interval{tstart},
		   tstop => $interval{tstop},
		   );

#    print Dumper %result;

    return \%result;

}


sub get_counts{
    my $arg_in = shift;
    my $mag_zoom_ref;
    if (defined $arg_in->{mag_zoom}){
	$mag_zoom_ref = $arg_in->{mag_zoom};
    }

    my %result;

    my %time_ranges = ( mission => $arg_in->{mission_interval},
		       report => $arg_in->{report_interval});

    my %config = %{$arg_in->{config}};

    my $handle = sql_connect( $config{task}->{db}->{connect_info} );

    my $exclude_bad_obsid = 'not in (select obsid from expected_bad_obsids)';    

    for my $select_range (keys %time_ranges ){

	my $time_range = $time_ranges{$select_range};
	my %result_range = ( name => $select_range,
			     tstart => $time_range->{tstart},
			     tstop => $time_range->{tstop},
			     );
	my %where = (
		     obsid => \$exclude_bad_obsid,      
		     type => { '!=' => 'FID'},
#		     id => { '!=' => '---' },
		     kalman_tstart => { '>=' => $time_range->{tstart} },
		     kalman_tstop => { '<=' => $time_range->{tstop} },
		     );					       


	my $default_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
						     fields => [ "count(id) as n" ],
						     where => \%where,
						 });
	
#	print $default_select->get_select_string(), "\n";

	my $all_stars =  $default_select->run({handle => $handle, type => 'array' })->[0]->{n};
	$result_range{all_stars} = $all_stars;
	$result_range{"sql_where"} = \%where;
	
	for my $rate_type ( keys %{$config{task}->{data}->{rates}} ){
	    my %make_select = %{$config{task}->{data}->{rates}->{$rate_type}};
	    
	    $default_select->add_where({ $make_select{field} => { $make_select{operator} => $make_select{value} }});

#	    print $default_select->get_select_string(), "\n";
	    
	    my $n_stars =  $default_select->run({handle => $handle, type => 'array'})->[0]->{n};



	    $result_range{"${rate_type}_stars"} = $n_stars;

	    $result_range{"${rate_type}_rate"} = $all_stars != 0 ? ( $n_stars / $all_stars) : 0;

	    # reset where
	    $default_select->where(\%where);

	}



	if (defined $mag_zoom_ref){
	    my %all_mag_bin;
	    for ( my $mag = $mag_zoom_ref->{mag_start}; $mag < $mag_zoom_ref->{mag_stop}; $mag += $mag_zoom_ref->{mag_bin} ){

		my $bin = $mag_zoom_ref->{mag_bin};
#		print "mag is $mag \n";
		my %mag_result;
		$mag_result{mag_start} = $mag;
		$mag_result{mag_stop} = ($mag + $bin);

		# copy the where
		my %mag_where;
		for my $key (keys %where){
		    $mag_where{$key} = $where{$key};
		}
		$mag_where{mag_exp} = { '>=' => $mag, 
					'<'  => $mag + $bin };

		$mag_result{"sql_where"} = \%mag_where;
#		print "$mag \n";
#		print Dumper \%where;
		$default_select->where(\%mag_where);

		my $mag_all_stars =  $default_select->run({handle => $handle, type => 'array' })->[0]->{n};
		$mag_result{all_stars} = $mag_all_stars;
	


		for my $rate_type ( keys %{$config{task}->{data}->{rates}} ){
		    my $n_stars;
		    if ($mag_all_stars == 0){
			$n_stars = 0;
		    }
		    else{
			my %make_select = %{$config{task}->{data}->{rates}->{$rate_type}};


			
			$default_select->add_where({ $make_select{field} => { $make_select{operator} => $make_select{value} }});

#		    print $default_select->get_select_string(), "\n";
		    
			$n_stars =  $default_select->run({handle => $handle, type => 'array'})->[0]->{n};


		    }
#		    print "n is $n_stars \n";



		    $mag_result{"${rate_type}_stars"} = $n_stars;
		    
		    $mag_result{"${rate_type}_rate"} = $mag_all_stars != 0 ? ( $n_stars / $mag_all_stars ) : 0;
		    
		    $default_select->where(\%mag_where);
		}


		$all_mag_bin{"$mag"} = \%mag_result;
	    }
	    
	    $result_range{mag_bins} = \%all_mag_bin;

	}


	$result{$select_range} = \%result_range;

    }

    
#    my $count_bad_ref = $select->run({handle => $handle, type => 'array' });
#    my $count_bad = $count_bad_ref->[0]->{n};
#
#    # total failures
#    $select->add_where({ 'percent_not_tracking' => 100 });
#
#    my $count_fail_ref = $select->run({handle => $handle, type => 'array' });
#    my $count_fail = $count_fail_ref->[0]->{n};
#

#    print Dumper %result;
    return \%result;
}




sub make_plots{

#=pod
#
#  * make_plots({ config => \%config, opt => \%opt }).
#
#Creates either a histogram or a scatter plot of guide success.
#Intended to be called by the separate make_plots.pl script.
#The type of plot is defined in $opt{type} and must be one of 'histogram' or 'scatter'/
#The time range is defined in $opt{tstart} to $opt{tstop}.
#The save location is defined in $opt{save_path}
#
#The database handle type, the database table for the queries, and the bad telemetry 
#threshold must be present in the config hash at $config{task}->{db}->{connect_info},
#$config{task}->{db}->{table} and $config{task}->{bad_telem_threshold}.
#
#
#=cut
#
    
    my $arg_in = shift;
    my %config = %{$arg_in->{config}};
    my %opt = %{$arg_in->{opt}};

    my %interval = %{define_interval({ tstart => $opt{tstart},
				       tstop => $opt{tstop}}) };
    
    my $BAD_PERCENT = $config{task}->{bad_telem_threshold};
    
    $ENV{PGPLOT_BACKGROUND} = 'white';
    $ENV{PGPLOT_FOREGROUND} = 'black';
    
    my $handle = sql_connect( $config{task}->{db}->{connect_info} );
    

    my $save_prefix = qq{};
#    if (defined $opt{save_string}){
#	$save_prefix = $opt{save_string};
#    }
    if (defined $opt{save_path}){
	if (defined $opt{predefined}){
	    $save_prefix .= $WEBDATA . "/" . $opt{save_path} . "/";
	    $opt{save_path} = $WEBDATA . "/" . $opt{save_path};
	}
	else{
	    $save_prefix .= $opt{save_path} . "/";
	}
    }
    
#    print "save prefix is $save_prefix \n";
    
    my @plots = keys %{$config{task}->{plots}};

    for my $plot (@plots){
#	print "$plot \n";
	my %plotcfg = %{$config{task}->{plots}->{$plot}};
#	use Data::Dumper;
#	print Dumper %plotcfg;
	my @plot_array;
	my $plot_islog = 0;

	# make the silly array/hash that pgs_plot
	if ( defined $plotcfg{pgs_plot}){
	    for my $pgs_elem (@{$plotcfg{pgs_plot}}){
		for my $key (keys %{$pgs_elem}){ 
		    push @plot_array, $key => $pgs_elem->{$key};
		    if ($key eq 'logy'){
			$plot_islog = $pgs_elem->{$key};
		    }
		}
						 
	    }

	}

#	print "curr plot array\n";
#	use Data::Dumper;
#	print Dumper @plot_array;

	if ($plot =~ /histogram/){
#	    print "$plot is histogram \n";
#=pod
#
#For a histogram, the range and bin size must be specified in the config hash as
#$config{task}->{histogram}->{mag_start}, $config{task}->{histogram}->{mag_stop}, and
#$config{task}->{histogram}->{mag_bin}.
#
#=cut

	    my $bin_type = $plotcfg{bin_over};
	    
	    my $start = $plotcfg{start};
	    my $stop =  $plotcfg{stop};
	    my $bin_size =  $plotcfg{bin};
	    
	    
	    my @bad_x100;
	    my @good;
	    my @data_bin;
	    
	    for ( my $bin = $start; $bin < $stop; $bin += $bin_size ){
		
		push @data_bin, $bin;
		
		my $bad_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
						     fields => [ "count(*) as not_tracked" ],
							 where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
								    'percent_not_tracking' => { '>=' => $BAD_PERCENT },
#								      percent_not_tracking => { '>=' => $BAD_PERCENT },
								    type => { '!=' => 'FID'},
								    kalman_tstart => { '>=' => $interval{tstart} },
								    kalman_tstop => { '<=' => $interval{tstop} },
								},					       
						     });

#	print $bad_track_select->get_select_string();
		
		my $answer_ref = $bad_select->run({ handle => $handle, type => 'array' });
		push @bad_x100, $answer_ref->[0]->{not_tracked}*100;
#	    print "at $mag, bad=", $answer_ref->[0]->{not_tracked}*100, "\n";
		
	    
		my $good_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
							  fields => [ "count(*) as tracked" ],
							  where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
								     'percent_not_tracking'  => { '<' => $BAD_PERCENT },
								     type => { '!=' => 'FID' },
								     kalman_tstart => { '>=' => $interval{tstart} },
								     kalman_tstop => { '<=' => $interval{tstop} },
								     
								 },						
						      });
		
#	    print $good_track_select->get_select_string();

		my $good_ref = $good_select->run({ handle => $handle, type => 'array' });
		
		push @good, $good_ref->[0]->{tracked};
	    }

#	    print Dumper @data_bin;
#	    print Dumper @good;
#	    print Dumper @bad_x100;

	    # find min non-zero value
	    my $good_pdl = pdl(@good);
	    my $min_non_zero = $good_pdl->( which( $good_pdl > 0) )->min();
	    my $y_good = $plot_islog ? $good_pdl + ($min_non_zero/10.) : $good_pdl;
	    my $bad_pdl = pdl(@bad_x100);
	    my $y_bad = $plot_islog ? $bad_pdl + ($min_non_zero/10.) : $bad_pdl;

	    push @plot_array,   
	    'x' => pdl(@data_bin),
	    'y' => $y_good,
	    options => {center => 1},
	    charsize => {symbol => 0.7,
			 title => 2.0,
			 axis => 2.0,
		     },
	    plot => 'bin',
	    'x' => pdl(@data_bin)+0.01,
	    'y' => $y_bad,
	    options => {center => 1},
	    charsize => {symbol => 0.7,
			 title => 2.0,
			 axis => 2.0,
		     },
	    color => { line => 'red' },
	    plot => 'bin',
	    ;

		


	}
    
	    
	  #	print scalar(@mag_bin), ":", scalar(@good_track), ":", scalar(@bad_track_x100), ":", scalar(@bad_color_x100), ":", scalar(@good_color), "\n";
	    
	    # if anything is defined in the config file, use it
	    
	    
	    if ($plot =~ /scatter/){
#		print "$plot is scatter \n";
		my $all_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
							 fields => [ "$plotcfg{x} as x", "$plotcfg{y} as y"],
							 where =>  { type => { '!=' => 'FID'},
								     kalman_tstart => { '>=' => $interval{tstart} },
								     kalman_tstop => { '<=' => $interval{tstop} },
								 },
						     });
		
		my $query = $all_select->get_select_string();
		
#    print "query is $query \n";
		
		my $sqlh= $handle->prepare($query);
		$sqlh->execute();
		my @x;
		my @y;
		while( my $star = $sqlh->fetchrow_hashref()){

		    push @x, $star->{x};
		    push @y, $star->{y};
		}
		
#		$handle->disconnect();
		
		my @label = ( 
			      );
		
#		 'x' => [[ $mag_plot_start, $mag_plot_stop ]],
#		 'y' => [[ ($BAD_PERCENT)/100., ($BAD_PERCENT)/100. ]],
#		 color => { line => 'red' },
#		 plot => 'line',

		# find min non-zero value
		my $good_pdl = pdl(@y);
		my $min_non_zero = $good_pdl->( which( $good_pdl > 0) )->min();
		my $y = $plot_islog ? $good_pdl + ($min_non_zero/10.) : $good_pdl;
		
		push @plot_array, 
		'x' => pdl(@x),
		'y' => $y,
		options => {center => 1},
		charsize => {symbol => 0.7,
			     title => 2.0,
			     axis => 2.0,
			 },
		@label,
		plot => 'points',
		;
		
	    }
	    

	    
	    my $plot_name = $plotcfg{plot_name};
	    $plot_name =~ s/.gif$/.ps/;
	    my $file = $plot_name . "/vcps";

#	    use Data::Dumper;
#	    print Dumper @plot_array;
	    
	    unless ($opt{dryrun}){
		if (defined $opt{save_path}){
		    mkpath( $opt{save_path}, 1 );
		}
		$file = $save_prefix . $file;
		pgs_plot( 
			  ny => 1,
			  xsize => 7,
			  ysize => 3.5,
			  device => $file,
			  @plot_array,
			  );
		$file =~ s/\/vcps$//;
		my $psfile = $file;
		$file =~ s/\.ps/.gif/;
		run("convert -antialias $psfile $file");
		unlink "$psfile";
		
	    }
	}	
	
}



1;






