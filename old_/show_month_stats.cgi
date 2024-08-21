#!/usr/bin/env /proj/sot/ska/bin/perl

use strict;
use warnings;

use diagnostics;
use CGI qw{ :standard -no_undef_params};
#use CGI::Carp qw{ fatalsToBrowser };

use IO::All;

my $gs_data = '/proj/sot/ska/www//ASPECT/guide_stat_reports/';
my $web_dir = 'http://cxc.harvard.edu/mta/ASPECT/guide_stat_reports/';

my $app = new CGI;

if ($app->param()){

    my $param_href= $app->Vars;    
    
    use Data::Dumper;
    #    print Dumper $param_href;
    
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
	    if (defined $param_href->{page}){
		if( $param_href->{page} =~ /Month/){
		    if( good_date($param_href) ){
			my $page = $param_href->{page};
			my $month = $param_href->{month};
			my $year = $param_href->{year};
			clear_params( $param_href);
			use Date::Tie;
			my $curr_month = Date::Tie->new( year => $year,
							 month => $month,
							 day => 1 );
			my $new_month = $curr_month->new();
			if ( $page eq 'NextMonth' ){
			    $new_month->{month}++;
			}
			if ( $page eq 'PrevMonth' ){
			    $new_month->{month}--;
			}
			$param_href->{month} = $new_month->{month};
			$param_href->{year} = $new_month->{year};
			print $app->redirect( -url => $app->self_url );
		    }
		}
		if ($param_href->{page} eq 'MainList'){
		    clear_params( $param_href );
		    print $app->header(),
		    $app->start_html('Guide Stat Reports');
		    print "\n";
		    my $report_list = list_reports();
		    print $report_list, "\n";
		    $app->end_html();
		    print "\n";
		}
	    }
	    else{
	    print $app->header(),
	    $app->start_html('Guide Stat Reports');
	    print "\n";
	    
	    
	    # display the form again, with any params filled in
	    
	    my $text = make_page({ cgi => $app, param => $param_href });
	    print $text;
	    
	    
	    my $report_text;
	    if (good_date($param_href)){
		$report_text = show_report({ cgi => $app,
					     param => $param_href,
					     year => $param_href->{year},
					     month => $param_href->{month},
					     data_dir => $gs_data });
	    }
	    print $report_text;
	    
#	    my $acq_stars_arr_ref = get_stars($param_href);
	    
#	    my $form = display_form({ cgi => $app, param => $param_href });
#	    print $form;
	    
#	    my $stars = display_data( $acq_stars_arr_ref );
#	    print $stars;
	    
	    
#	    print "\n";
	    print $app->end_html();
	    print "\n";
	}
   	}
    }
}
    
else{
    
    print $app->header(),
    $app->start_html('Guide Stat Reports');
    print "\n";
    
# if the form has not been submitted, display the form
    
    my $text = make_page({ cgi => $app });
    print $text;
#    my $form = display_form({ cgi => $app });
#    print $form;
#    print "\n";
    print $app->end_html();
    print "\n";
}
#
#

sub good_date{
    my $param_href = shift;
    
    if (defined $param_href->{year}){
	unless ($param_href->{year} =~ /^\d{4}$/){
	    croak("Year should be 4 digits \n");
	}
	if (not defined $param_href->{month}){
	    croak("Month must be defined \n");
	}
    }
    if (defined $param_href->{month}){
	unless ($param_href->{month} =~ /^\d{2}$/){
	    croak("Month should be 2 digits \n");
	}
	if (not defined $param_href->{month}){
	    croak("Year must be defined \n");
	}
    }

    if( defined $param_href->{year} and defined $param_href->{month}){
	return 1;
    }
    
    return 0;
}


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

sub make_page{

#sub display_page{

    use Data::Dumper;
    my $arg_in = shift;
#    print Dumper $arg_in;
    my $query = $arg_in->{cgi};
    my $param_href;
    if (defined $arg_in->{param}){
	$param_href = $arg_in->{param};
    }
#    print $query->self_url;
#    print Dumper $query;

 
    my @param_list = qw( month year page);;
#    for my $listkey (@{$config{pieces}}){
#	push @param_list, @{$config{$listkey}};
#    }
#
##    print Dumper @param_list;
#
#
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
#    
#
#
    my $page = qq{};
#    for my $mode qw(MainList NextMonth PreviousMonth){
#	$page .= "<A HREF=" . $query->self_url() . "?mode=$mode>$mode</A><BR />\n";
#    }
#    	$page .= "<A HREF=" . $query->self_url() . "?action='Clear'>Reset</A><BR />\n";
#    print $page;

    my $form =  $query->start_form(-method => 'GET');
#   $form .= '<table width="750"><tr><td>';
#    $form .= $query->h2({-style=>'Color: #990000;'}, "Guide Statistics Database Search Form");
##    
###    $form .=  "<P>Enter your search parameters to bring up a portion of the acquisition statistics database.<p>Start and stop times may be entered in either YYYY:DDD:hh:mm:ss.ss... or Chandra time formats.  All catalog magnitudes, y-angles, and z-angles are AGASC 1.6 numbers where possible.<P>This database is dependent on the archive, so very recent observations may not be available.<P>";
##    
#    $form .=  $query->h3( {-style=>'Color: #990000;'}, "Enter parameters:");
#    $form .= "<table>\n";
#    for my $poss_param (@param_list){
#
#	my @poss_param_arr;
#	if (( grep( /^${poss_param}$/, @{$config{range_field}})) 
#	      or (grep( /^${poss_param}$/, @{$config{percent_field}}))){
#	    push @poss_param_arr, ( "${poss_param}_beg", "${poss_param}_end" );
#	}
#	else{
#	    push @poss_param_arr, ( "$poss_param" );
#	}
##	print Dumper @poss_param_arr;
#	for my $entry (@poss_param_arr){
#	my $text;
##	    print "entry is $entry \n";
#	$text .= "<tr><td>$entry</td><td>\n";
#	$text .= $query->textfield(-name=>"$entry",
#				   -default=>$passed_param{"$entry"},
#				   -override => 1,
#				   -size=>10,
#				   -maxlength=>10);
#	$text .= "\n";
#	$text .= "</td></tr>\n";
#	$form .= $text;
#    }
#    }
#
#    $form .= "</table>";
#
#    $form .=  $query->submit();
#    $form .= "<tr><td>";
    $form .=  $query->submit( -name => 'page',
			      -value => 'MainList',
			      );
    $form .= "<br />\n";
    $form .= "Month YYYY-MM : ";
    $form .=  $query->textfield(-name=> "year",
				-default=>$passed_param{"year"},
				-override => 1,
				-size=> 4,
				-maxlength => 4);
    $form .= "-";
    $form .=  $query->textfield(-name=> "month",
				-default=>$passed_param{"month"},
				-override => 1,
				-size=> 2,
				-maxlength => 2);
    $form .= $query->submit();
    $form .= "<br />\n";
    
    $form .=  $query->submit( -name => 'page',
			      -value => 'NextMonth',
			      );
    $form .=  $query->submit( -name => 'page',
			      -value => 'PrevMonth',
			      );
#    $form .=  $query->reset();
    $form .=  $query->submit( -name => 'action',
			      -value => 'Clear'
			      );
#
#    $form .=  "<p>";
#    
    $form .= $query->end_form();
#    $form .= "</td></table>";
#
#
#    return $page;
#
#}

    $page .= $form;
    return $page;;


}

sub show_report{

    my $arg_in = shift;
    my $query = $arg_in->{cgi};
#    my $param_href;
#    if (defined $arg_in->{param}){
#	$param_href = $arg_in->{param};
#    }
    my $month = $arg_in->{month};
    my $year = $arg_in->{year};
    my $data_dir = $arg_in->{data_dir};

    my $month_dir = "${data_dir}/${year}/${month}/";
    my $month_web_dir = "${web_dir}/${year}/${month}/";
    my $report_name = 'gs_report.txt';
    my $image1 = 'scatter.gif';
    my $image2 = 'histogram.gif';

    my $text;
    use IO::All;
    if ( -d ${month_dir} ){
	my $report_txt = io("${month_dir}/$report_name")->slurp;

	# rough report text "
	$text .= "<pre>";
	$text .= $report_txt;
	$text .= "</pre><br/>\n";
	$text .= "<IMG SRC=\"${month_web_dir}/${image1}\"><br />\n";
	$text .= "<IMG SRC=\"${month_web_dir}/${image2}\"><br />\n";
    }
    else{
	$text = "No data available for specified month \n";
    }

    return $text;
}
 


sub list_reports{

    my $data_dir = $gs_data;
    my @year_dirs = glob("${data_dir}/????");
    my @months = qw( 01 02 03 04 05 06 07 08 09 10 11 12 );

    my $url = $app->self_url();

    my $list;
    $list .= "<table>\n";
    for my $year_dir (@year_dirs){
	$year_dir =~ /.*\/(\d{4})\/?$/;
	my $year = $1;
	$list .= "<tr><td>$year</td>";
	for my $month (@months){
	    if ( -d "${data_dir}/${year}/${month}" ){
		$list .= "<td><a href=\"$url?month=${month};year=${year}\">$month</A></td>";
	    }
	    else{
		$list .= "<td>ND</td>";
	    }
	}
	$list .= "</tr>\n";
    }
    $list .= "</table>";

    return $list;

    

}
