#!/usr/bin/env /proj/sot/ska/bin/perl

use strict;
use warnings;
#use diagnostics;

#use Getopt::Long;

use Ska::SQL::Select;

#use CGI::Carp qw{ fatalsToBrowser };

use Ska::DatabaseUtil qw{ sql_connect };

use CGI qw{ :standard -no_undef_params};

use Chandra::Time;

use Data::Dumper;

my $app = new CGI;

# if there are any parameters

my @top_field = ( 'obsid', 'obi', 'slot', 'type', 'agasc_id');

my @range_field = ( 'kalman_tstart', 'kalman_tstop', 
		    'yang_exp', 'zang_exp', 'mag_exp',
		    'yang_obs_mean', 'zang_obs_mean', 'mag_obs_mean' );

my @percent_field = ( 'percent_not_tracking', 'percent_obc_bad_status');

my %abbrev = ( 'kalman_tstart' => 'tstart',
	       'kalman_tstop' => 'tstop',
	       'percent_not_tracking' => 'NT %',
	       'percent_obc_bad_status' => 'BS %',
	       );

my %type_regex = ( angle => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
		   mag =>  '(\d+\.\d+|\d+\.?|\.\d+)',
		   percent => '(\d+\.\d+|\d+\.?|\.\d+)' ,
		   );


#    my %range_regex = (
#		       mag => '(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       yang => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       zang => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       yang_obs => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       zang_obs => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       d_yang => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       d_zang => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       d_mag => '[+-]?(\d+\.\d+|\d+\.?|\.\d+)' ,
#		       );



my %config = ( 'db_connect_info' => 'sybase-aca-aca_read',
	       'table' => 'guide_stats_view',
	       'pieces' => [ 'top_field', 'range_field', 'percent_field' ],
	       'top_field' => \@top_field,
	       'range_field' => \@range_field,
	       'percent_field' => \@percent_field,
	       'abbrev' => \%abbrev );

#print Dumper %config;
#
#my $obsid = '7406';
#
#my $handle = sql_connect( $config{db_connect_info} );
#
#my $select = Ska::SQL::Select->new({  
#    table => $config{table}, 
#    fields => ['*'], 
#    order => ['kalman_tstart'],
#    where => { obsid => $obsid },
# });
#
#my $array_ref = $select->run({handle => $handle, type => 'array'});
#print Dumper $select->{select_string};
#print Dumper $array_ref;





if ($app->param()){

    my $param_href= $app->Vars;    

    if (defined $param_href->{action}){
	if ($param_href->{action} eq 'Clear'){
	    clear_params( $param_href);
	    print $app->redirect( -url => $app->self_url );
	}
    }
    else{
	# I like the GET URL syntax, but I hate the undef params
	# let's strip them and redirect to a pretty URL
	if ( has_null_param( $param_href ) ){
	    strip_nulls( $param_href );
	    print $app->redirect( -url => $app->self_url );
	}
	else{

	    print $app->header(),
	    $app->start_html('Guide Stat Query');
	    print "\n";
	    # display the form again, with any params filled in
	    
	    my $acq_stars_arr_ref = get_stars($param_href);
	    
	    my $form = display_form({ cgi => $app, param => $param_href });
	    print $form;
	    
	    my $stars = display_stars( $acq_stars_arr_ref );
	    print $stars;
	    
	    
	    print "\n";
	    print $app->end_html();
	    print "\n";
	    
	}
    }
}
else{

    print $app->header(),
          $app->start_html('Guide Stat Query');
    print "\n";

# if the form has not been submitted, display the form

    my $form = display_form({ cgi => $app });
    print $form;
    print "\n";
    print $app->end_html();
    print "\n";
}
#
#
sub has_null_param{

    my $param_href = shift;

    for my $key (keys %{$param_href}){
        if ($param_href->{$key} =~ /^$/){
	    return 1;
        }
    }
    return 0;
}

sub clear_params{
    my $param_href = shift;

    for my $key (keys %{$param_href}){
            delete $param_href->{$key};
    }
}
    

sub strip_nulls{

    my $param_href = shift;

    for my $key (keys %{$param_href}){
        if ($param_href->{$key} =~ /^$/){
            delete $param_href->{$key};
        }
    }

}


sub display_form{


    my $arg_in = shift;
    my $query = $arg_in->{cgi};
    my $param_href;
    if (defined $arg_in->{param}){
	$param_href = $arg_in->{param};
    }
#
##
###    print $query->header(-type=>'text/html',-cache=>'no-cache',-expires=>'now');
###
###
###    print $query->start_html(-title => "Acquisition Database Search Form",
###                         -background => "http://asc.harvard.edu/mta/ASPECT/blue_paper.gif",
###                         -TEXT    => 'black');
##
#    my @param_list = ( 'agasc_id', 
#		       'obsid', 
#		       'tstart_beg', 
#		       'tstart_end', 
#		       'mag_beg', 
#		       'mag_end', 
#		       'yang_beg', 
#		       'yang_end', 
#		       'zang_beg', 
#		       'zang_end',
#		       'mag_obs_mean_beg',
#		       'mag_obs_mean_end',
#		       'yang_obs_mean_beg',
#		       'yang_obs_mean_end',
#		       'zang_obs_mean_beg',
#		       'zang_obs_mean_end',
#		       'percent_not_tracking_beg',
#		       'percent_not_tracking_end',
#		       'percent_obc_bad_status_beg',
#		       'percent_obc_bad_status_end',
#		       );
# 
    my @param_list;
    for my $listkey (@{$config{pieces}}){
	push @param_list, @{$config{$listkey}};
    }

#    print Dumper @param_list;


    my %passed_param;

    for my $in_param (@param_list){
	if (defined $param_href->{$in_param}){
	    $passed_param{$in_param} = $param_href->{$in_param};
	}
	else{
	    $passed_param{$in_param} = qq{};
	}
    }

#    print Dumper %passed_param;
    


    my $form =  $query->start_form(-method => 'GET');
    $form .= '<table width="750"><tr><td>';
    $form .= $query->h2({-style=>'Color: #990000;'}, "Guide Statistics Database Search Form");
#    
##    $form .=  "<P>Enter your search parameters to bring up a portion of the acquisition statistics database.<p>Start and stop times may be entered in either YYYY:DDD:hh:mm:ss.ss... or Chandra time formats.  All catalog magnitudes, y-angles, and z-angles are AGASC 1.6 numbers where possible.<P>This database is dependent on the archive, so very recent observations may not be available.<P>";
#    
    $form .=  $query->h3( {-style=>'Color: #990000;'}, "Enter parameters:");
    $form .= "<table>\n";
    for my $poss_param (@param_list){

	my @poss_param_arr;
	if (( grep( /^${poss_param}$/, @{$config{range_field}})) 
	      or (grep( /^${poss_param}$/, @{$config{percent_field}}))){
	    push @poss_param_arr, ( "${poss_param}_beg", "${poss_param}_end" );
	}
	else{
	    push @poss_param_arr, ( "$poss_param" );
	}
#	print Dumper @poss_param_arr;
	for my $entry (@poss_param_arr){
	my $text;
#	    print "entry is $entry \n";
	$text .= "<tr><td>$entry</td><td>\n";
	$text .= $query->textfield(-name=>"$entry",
				   -default=>$passed_param{"$entry"},
				   -override => 1,
				   -size=>10,
				   -maxlength=>10);
	$text .= "\n";
	$text .= "</td></tr>\n";
	$form .= $text;
    }
    }

##    $form .= "<table><tr>";
##    $form .= "<th></th><th></th></tr>";
##    $form .= "<tr><td>";
#    $form .= "<table>";
#    $form .= "<tr><td>AGASC ID</td><td>";
##    $form .=  "<p> &nbsp AGASC ID ";
#    $form .=  $query->textfield(-name=>'agasc_id',
#			    -default=>$passed_param{'agasc_id'},
#			    -override=>1,
#			    -size=>10,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
##    $form .=  "<p> &nbsp OBC ID ";
##    $form .= "<tr><td>OBC ID</td><td>";
##    $form .=  $query->textfield(-name=>'obc_id',
##			    -default=>$passed_param{'obc_id'},
##			    -override=>1,
##			    -size=>10,
##			    -maxlength=>10);
##    $form .= "</td></tr>";
#    $form .= "<tr><td>Obsid</td><td>";
##    $form .=  "&nbsp Obsid ";
#    $form .=  $query->textfield(-name=>'obsid',
#			    -default=>$passed_param{'obsid'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
##    $form .= "</td></tr>";
##    $form .= "<tr><td>Mission Planning Load</td><td>";
##    $form .=  "&nbsp Mission Planning Load ";
##    $form .=  $query->textfield(-name=>'mp_path',
##			    -default=>$passed_param{'mp_path'},
##B			    -size=>20,
##			    -override=>1,
##			    -maxlength=>20);
#    $form .= "</td></tr></table>";
##    $form .= "</td>";
##    $form .= "<td>";
#
#    $form .= "<table>";
#    $form .= "<tr><td>Kalman Start Time Interval</td><td>";
##    $form .=  "<p>&nbsp Observation Start Time Interval ";
#    $form .=  $query->textfield(-name=>'tstart_beg',
#			    -default=>$passed_param{'tstart_beg'},
#			    -size=>21,
#			    -override=>1,
#			    -maxlength=>21);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'tstart_end',
#			    -default=>$passed_param{'tstart_end'},
#			    -size=>21,
#			    -override=>1,
#			    -maxlength=>21);
#
#    $form .= "</td></tr>";
#    
#    $form .= "<tr><td>Magnitude (MAG_ACA) Interval</td><td>";
##    $form .=  "<p>&nbsp Magnitude (MAG_ACA) Interval ";
#    $form .=  $query->textfield(-name=>'mag_beg',
#			    -default=>$passed_param{'mag_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'mag_end',
#			    -default=>$passed_param{'mag_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#
#    $form .= "<tr><td>Y-Angle (CCD) Interval (yang)</td><td>";
##    $form .=  "<p>&nbsp Y-Angle (CCD) Interval (yang) ";
#    $form .=  $query->textfield(-name=>'yang_beg',
#			    -default=>$passed_param{'yang_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'yang_end',
#			    -default=>$passed_param{'yang_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#    
#    $form .= "<tr><td>Z-Angle (CCD) Interval (zang)</td><td>";
##    $form .=  "<p>&nbsp Z-Angle (CCD) Interval (zang)";
#    $form .=  $query->textfield(-name=>'zang_beg',
#			    -default=>$passed_param{'zang_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'zang_end',
#			    -default=>$passed_param{'zang_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#
#    $form .= "<tr><td>Observed MAG_ACA Interval (mag_obs) </td><td>";
##    $form .=  "<p>&nbsp Observed MAG_ACA Interval (mag_obs)";
#    $form .=  $query->textfield(-name=>'mag_obs_beg',
#			    -default=>$passed_param{'mag_obs_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'mag_obs_end',
#			    -default=>$passed_param{'mag_obs_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#    $form .= "<tr><td>Observed Yang Interval (yang_obs) </td><td>";
##        $form .=  "<p>&nbsp Observed Yang Interval (yang_obs)";
#    $form .=  $query->textfield(-name=>'yang_obs_beg',
#			    -default=>$passed_param{'yang_obs_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'yang_obs_end',
#			    -default=>$passed_param{'yang_obs_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#    $form .= "<tr><td>Observed Zang Interval (zang_obs) </td><td>";
##    $form .=  "<p>&nbsp Observed Zang Interval (zang_obs)";
#    $form .=  $query->textfield(-name=>'zang_obs_beg',
#			    -default=>$passed_param{'zang_obs_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'zang_obs_end',
#			    -default=>$passed_param{'zang_obs_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#   
#    $form .= "<tr><td>Not tracking percent</td><td>";
##    $form .=  "<p>&nbsp Catalog vs Observed Mag, Interval (d_mag) ";
#    $form .=  $query->textfield(-name=>'percent_not_tracking_beg',
#			    -default=>$passed_param{'percent_not_tracking_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'percent_not_tracking_end',
#			    -default=>$passed_param{'percent_not_tracking_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#
#    $form .= "<tr><td>OBC bad status percent</td><td>";
##    $form .=  "<p>&nbsp Catalog vs Observed Mag, Interval (d_mag) ";
#    $form .=  $query->textfield(-name=>'percent_obc_bad_status_beg',
#			    -default=>$passed_param{'percent_obc_bad_status_beg'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td><td>to</td><td>";
##    $form .=  "&nbsp to &nbsp ";
#    $form .=  $query->textfield(-name=>'percent_obc_bad_status_end',
#			    -default=>$passed_param{'percent_obc_bad_status_end'},
#			    -size=>10,
#			    -override=>1,
#			    -maxlength=>10);
#    $form .= "</td></tr>";
#
#
##    $form .= "<tr><td>Catalog vs Observed Mag, Interval (d_mag) </td><td>";
###    $form .=  "<p>&nbsp Catalog vs Observed Mag, Interval (d_mag) ";
##    $form .=  $query->textfield(-name=>'d_mag_beg',
##			    -default=>$passed_param{'d_mag_beg'},
##			    -size=>10,
##			    -override=>1,
##			    -maxlength=>10);
##    $form .= "</td><td>to</td><td>";
###    $form .=  "&nbsp to &nbsp ";
##    $form .=  $query->textfield(-name=>'d_mag_end',
##			    -default=>$passed_param{'d_mag_end'},
##			    -size=>10,
##			    -override=>1,
##			    -maxlength=>10);
##    $form .= "</td></tr>";
##    $form .= "<tr><td>Catalog vs Observed Yang, Interval (d_yang) </td><td>";
###    $form .=  "<p>&nbsp Catalog vs Observed Yang, Interval (d_yang) ";
##    $form .=  $query->textfield(-name=>'d_yang_beg',
##			    -default=>$passed_param{'d_yang_beg'},
##			    -size=>10,
##			    -override=>1,
##			    -maxlength=>10);
##    $form .= "</td><td>to</td><td>";
## #   $form .=  "&nbsp to &nbsp ";
##    $form .=  $query->textfield(-name=>'d_yang_end',
##			    -default=>$passed_param{'d_yang_end'},
##			    -size=>10,
##			    -override=>1,
##			    -maxlength=>10);
##    $form .= "</td></tr>";
##    $form .= "<tr><td>Catalog vs Observed Zang, Interval (d_zang) </td><td>";
###    $form .=  "<p>&nbsp Catalog vs Observed Zang, Interval (d_zang) ";
##    $form .=  $query->textfield(-name=>'d_zang_beg',
##			    -default=>$passed_param{'d_zang_beg'},
##			    -size=>10,
##			    -override=>1,
##			    -maxlength=>10);
##    $form .= "</td><td>to</td><td>";
## #   $form .=  "&nbsp to &nbsp ";
##    $form .=  $query->textfield(-name=>'d_zang_end',
##			    -default=>$passed_param{'d_zang_end'},
##			    -size=>10,
##			    -override=>1,
##			    -maxlength=>10);
##    $form .= "</td></tr>";
    $form .= "</table>";
##    $form .= "</td></tr></table>";
#    
    $form .=  $query->submit();
    $form .=  $query->reset();
    $form .=  $query->submit( -name => 'action',
			      -value => 'Clear'
			      );

    $form .=  "<p>";
    
    $form .= $query->end_form();
    $form .= "</td></table>";


    return $form;

}
#
#
#
#
#
sub check_and_change_times{
    # overwrite the param hash ref in place with chandra times as needed
    my $param_href = shift;
    my @times = ('kalman_tstart_beg', 'kalman_tstart_end', 'kalman_tstop_beg', 'kalman_tstop_end');
    for my $time (@times){
	if (defined $param_href->{$time}){
	    my $ct_time = Chandra::Time->new($param_href->{$time});
	    $param_href->{$time} = $ct_time->secs();
	}

    }

}
#
#
sub get_stars{

    my $param_href = shift;

#    print Dumper $param_href;
#
##    my %where;
#    my @plain_vars = ( 'agasc_id', 'obsid', 'obi', 'slot' );
#    my @range_vars = ( 'kalman_tstart', 'mag', 'yang', 'zang', 'mag_obs_mean', 'yang_obs_mean', 'zang_obs_mean', 'percent_not_tracking', 'percent_obc_bad_status' );
#
    my $select = Ska::SQL::Select->new({  
	table => $config{table}, 
	fields => ['*'], 
	order => ['kalman_tstart'],
	
    });


    for my $keyword (@{$config{top_field}}){
	if (defined $param_href->{$keyword}){
		$select->add_where({ $keyword => $param_href->{$keyword}});
	}
    }

##    print Dumper $select;
#
    for my $range_type (@{$config{range_field}}, @{$config{percent_field}}){
	my %range_holder;
	my $beg = "${range_type}_beg";
	my $end = "${range_type}_end";
	if (defined $param_href->{$range_type}){
#	    print "first if \n";
	    if (defined $range_regex{$range_type}){
#		print "second if \n";
		if ($param_href->{$range_type} =~ /^($range_regex{$range_type})?\:($range_regex{$range_type})?$/ ){
		    $param_href->{$beg} = $1;
		    $param_href->{$end} = $3;
		    delete $param_href->{$range_type};
		}
		else{
		    unless ($param_href->{$range_type} =~ /^($range_regex{$range_type})$/ ){
			# print an error
			delete $param_href->{$range_type};
		    }
		}
		
	    }
	    else{
		if ($param_href->{$range_type} =~ /(.*)::(.*)/){
#		    print "second regexp \n";
		    $param_href->{$beg} = $1;
		    $param_href->{$end} = $2;
		    delete $param_href->{$range_type};
		}
		else{
		    if ($param_href->{$range_type} =~ /(.*):(.*)/){
#		    print "second regexp \n";
			$param_href->{$beg} = $1;
			$param_href->{$end} = $2;
			delete $param_href->{$range_type};
		    }
		}
	    }
	}
	print Dumper $param_href;
#
#	check_and_change_times($param_href);
#	strip_nulls($param_href);
#
#	if (defined $param_href->{$beg}){
#	    my $beg_data = $param_href->{$beg};
#	    $range_holder{'>='} = $beg_data;
#	}
#
#	if (defined $param_href->{"${range_type}_end"}){
#	    my $end_data = $param_href->{$end};
#	    $range_holder{'<='} = $end_data;
#	}
#
#	if (defined $param_href->{$range_type}){
#	    $range_holder{"="} = $param_href->{$range_type};
#	}
#
#	if (scalar(keys(%range_holder))){
#	    $select->add_where({ $range_type => \%range_holder });
#	}
#    }
#    
##    print "\n";
##    print Dumper $param_href;
##    print Dumper $select;
#
#    my $handle = sybase_readonly_connect();
#    my $array_ref = $select->run({handle => $handle, type => 'array'});
##    print Dumper $select->{select_string};
#
#    return $array_ref;

    return " ";
}
#
sub display_stars{
#
#
#    my $acq_stars_arr_ref = shift;
#
#    my $stars = qq{};
#    
#    my @outputs = qw( obsid obi slot kalman_tstart agasc_id type 
#		      mag yang zang mag_obs_mean yang_obs_mean zang_mean_obs d_mag d_yang d_zang);
#
#    my %output_hash = ( obsid => " %s ",
#			obi => " %s ",
#			slot => " %s ",
#			mp_path => " %s ",
#			tstart => " %s ",
#			agasc_id => " %s ",
#			obc_id => " %s ",
#			mag => "% 4.2f",
#			yang => "% 8.2f",
#			zang => "% 8.2f",
#			mag_obs => "% 4.2f",
#			yang_obs => "% 8.2f",
#			zang_obs => "% 8.2f",
#			d_mag => "% 3.2f",
#			d_yang => "% 8.2f",
#			d_zang => "% 8.2f",
#			);
#
##    use Data::Dumper;
##    print Dumper %output_hash;
#    my @my_acqs = @{$acq_stars_arr_ref};
#
#    $stars .= '<table width="500" border="1" >';
#    $stars .= '<tr>';
#    foreach (@outputs) { $stars .= "<td> $_ </td>" };
#    $stars .= '</tr>';
#    
#    for my $star (@my_acqs) {
#	my $obsid = $star->{obsid};
#	$stars .= '<tr>';
#	foreach my $key (@outputs) { 
#	    if (defined $star->{$key}){
#		$stars .= sprintf("<td align=right> $output_hash{$key} </td>", $star->{$key}) ;
#	    }
#	    else{
#		$stars .= '<td></td>';
#	    }
#	};
#	$stars .= '</tr>';
#	$stars .= "\n";
#    }
#
#    $stars .= '</table>';
#
#    if (scalar(@my_acqs) == 0){
#	$stars .= "<br><H2> No Acq Stars found with specified search criteria. </H2><br>\n";
#    }
#
#    return $stars;
#
    return " ";
}

