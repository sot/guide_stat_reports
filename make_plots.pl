#!/usr/bin/env perlska

use strict;
use warnings;

#use MLDBM qw(DB_File Storable);
#use Fcntl;
#use Storable;

use PDL;
use PDL::NiceSlice;
use PGPLOT::Simple qw( pgs_plot );
use Data::Dumper;
use Getopt::Long;

use Chandra::Time;

my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = gmtime(time);
my $year = 1900 + $yearOffset;
my $date_now = sprintf("%4d:%03d:%02d:%02d:%02d.000", $year, $dayOfYear, $hour, $minute, $second);
#my $date_minus_1y = sprintf("%4d:%03d:%02d:%02d:%02d.000", $year-1, $dayOfYear, $hour, $minute, $second);

my %opt = ( type => 'histogram',
	    tstop => $date_now,
	    tstart => '1999:001:00:00:00.000' );

GetOptions( \%opt,
	    "type=s",
	    "tstart=s",
	    "tstop=s",
	    );


use Carp;

my %interval;

for my $time_key qw( tstart tstop ){
    my $time = $opt{$time_key};
    my $time_obj;
    eval{
	$time_obj = Chandra::Time->new( $time );
	$interval{$time_key} = $time_obj->secs();
    };
    if ($@){
	croak("Could not parse $time_key using Chandra::Time \n");
    }
    
}

use YAML;
my %config = YAML::LoadFile("plots.yaml");

my $BAD_PERCENT = $config{task}->{bad_telem_threshold};


$ENV{PGPLOT_BACKGROUND} = 'white';
$ENV{PGPLOT_FOREGROUND} = 'black';


##my $ONE = 1.0001;		# Yeah...
##my $T_launch = 49118400.0;
##my %mag;
#
##GetOptions('year=s' => \$year) or die "Bad option\n";
##
##for $year (qw(2001 2002 2003 2004 2005)) {
##    print "Reading year $year\n";
##    tie (%s, 'MLDBM', "stats_${year}.dat", O_CREAT|O_RDWR, 0644) || die $!;
##
##    foreach my $obsid (keys %s) {
##	my $obs = $s{$obsid};
##	foreach my $star (@{$obs->{stars}}) {
##	    next if $star->{frac_track} > $ONE; # Argh, some bug in make_guide_stats related to month boundary
##	    next if $star_visited{$star->{ID}}; # Only look at a star once.  (Would be better to cumulate time
##	                                        # for each unique star)
##	    $star_visited{$star->{ID}} = 1;
##
##	    push @{ $star->{frac_track} > $GOOD_THRESH ? $mag{track} : $mag{no_track} }, $star->{MAG};
##	    push @{ $star->{frac_track_stat0} > $GOOD_THRESH ? $mag{track_stat0} : $mag{no_track_stat0} }, $star->{MAG};
##	    print "Yikes $obsid $star->{frac_track}\n" if $star->{frac_track} > $ONE;
##	}
##    }
##    untie %s;
##}
##
#
#

use Ska::DatabaseUtil qw( sql_connect );
use Ska::SQL::Select;

my $handle = sql_connect( $config{task}->{db}->{connect_info} );

if ( $opt{type} eq 'histogram' ){

    my $mag_start = $config{task}->{histogram}->{mag_start};
    my $mag_stop =  $config{task}->{histogram}->{mag_stop};
    my $bin =  $config{task}->{histogram}->{mag_bin};





    my @bad_track_x100;
    my @good_track;
    my @mag_bin;

    for ( my $mag = $mag_start; $mag < $mag_stop; $mag += $bin ){

	push @mag_bin, $mag;

	my $bad_track_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
						   fields => [ "count(*) as not_tracked" ],
						   where => { mag_exp => { '>=' => $mag, '<' => $mag + $bin },
							      percent_not_tracking => { '>=' => $BAD_PERCENT },
							      type => { '!=' => 'FID'},
							      kalman_tstart => { '>=' => $interval{tstart} },
							      kalman_tstop => { '<=' => $interval{tstop} },
							  },					       
					       });

#	print $bad_track_select->get_select_string();
	
	my $answer_ref = $bad_track_select->run({ handle => $handle, type => 'array' });
	push @bad_track_x100, $answer_ref->[0]->{not_tracked}*100;

    
	my $good_track_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
							fields => [ "count(*) as tracked" ],
							where => { mag_exp => { '>=' => $mag, '<' => $mag + $bin },
								   percent_not_tracking => { '<' => $BAD_PERCENT },
								   type => { '!=' => 'FID' },
								   kalman_tstart => { '>=' => $interval{tstart} },
								   kalman_tstop => { '<=' => $interval{tstop} },
								   
							       },						
						    });
	
	my $good_track_ref = $good_track_select->run({ handle => $handle, type => 'array' });
#    print Dumper $good_track_ref;
	push @good_track, $good_track_ref->[0]->{tracked};
#	print " at $mag, good=", $good_track_ref->[0]->{tracked}, ", bad=", $answer_ref->[0]->{not_tracked}, "\n";
    }


    my $color_start = $config{task}->{histogram}->{color_start};
    my $color_stop = $config{task}->{histogram}->{color_stop};
    my $cbin = $config{task}->{histogram}->{color_bin};

#for my $type ('', '_stat0') {
#    my ($x, $y) = hist( pdl($mag{"track$type"}), 5, 12, 0.25);
#    my ($xnt, $ynt) = hist( pdl($mag{"no_track$type"}), 5, 12, 0.25);
#
#    my $frac_nt = $ynt / ($y + $ynt + 1e-3);
#
#    # $ynt *= $mag_track->nelem / $mag_no_track->nelem;
#


    my @bad_color_x100;
    my @good_color;
    my @color_bin;
    
    for ( my $color = $color_start; $color < $color_stop; $color += $cbin ){
	
	push @color_bin, $color;

	my $bad_track_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
						       fields => [ "count(*) as not_tracked" ],
						       where => { color => { '>=' => $color, '<' => $color + $cbin },
								  percent_not_tracking => { '>=' => $BAD_PERCENT },
								  type => { '!=' => 'FID'},
								  kalman_tstart => { '>=' => $interval{tstart} },
								  kalman_tstop => { '<=' => $interval{tstop} },
							  },					       
					       });

#    print $select->get_select_string();

	my $answer_ref = $bad_track_select->run({ handle => $handle, type => 'array' });
	push @bad_color_x100, $answer_ref->[0]->{not_tracked}*100;

    
	my $good_track_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
							fields => [ "count(*) as tracked" ],
							where => { color => { '>=' => $color, '<' => $color + $cbin },
								   percent_not_tracking => { '<' => $BAD_PERCENT },
								   type => { '!=' => 'FID' },
								   kalman_tstart => { '>=' => $interval{tstart} },
								   kalman_tstop => { '<=' => $interval{tstop} },

							       },						
						    });
	
	my $good_track_ref = $good_track_select->run({ handle => $handle, type => 'array' });
#    print Dumper $good_track_ref;
	push @good_color, $good_track_ref->[0]->{tracked};
#	print " at $color, good=", $good_track_ref->[0]->{tracked}, ", bad=", $answer_ref->[0]->{not_tracked}, "\n";
	
    }

    my @label = ( 
		  );
    
    my @plot = ( 'x' => pdl(@mag_bin),
		 'y' => pdl(@good_track)+0.1,
		 panel => [1,1],
		 logy => 1,
		 lims => [$mag_start,$mag_stop, 0.2, undef],
		 options => {center => 1},
		 charsize => {symbol => 0.7,
			      title => 2.0,
			      axis => 2.0,
			  },
		 toptitle => "Mags for good (black) and bad (red) guide stars",
		 xtitle => 'Star magnitude (mag)',
		 ytitle => 'Number (red is x100)',
		 @label,
		 plot => 'bin',
		 'x' => pdl(@mag_bin),
		 'y' => pdl(@bad_track_x100)+0.1,
		 color => { line => 'red' },
		 plot => 'bin',
		 );

    my @plot2 = ( 'x' => pdl(@color_bin),
		  'y' => pdl(@good_color)+0.1,
		  panel => [1,2],
		  logy => 1,
		  lims => [$color_start,$color_stop, 0.2, undef],
		  options => {center => 1},
		  charsize => {symbol => 0.7,
			       title => 2.0,
			       axis => 2.0,
			   },
		  toptitle => "",
		  xtitle => 'Color',
		  ytitle => 'Number (red is x100)',
		  @label,
		  plot => 'bin',
		  'x' => pdl(@color_bin),
		  'y' => pdl(@bad_color_x100)+0.1,
		  color => { line => 'red' },
		  plot => 'bin',
		  );


    my $file = $config{task}->{histogram}->{plot_name} . "/vcps";
#
#    print "file is $file \n";
    pgs_plot( 
	      ny => 2,
	      xsize => 6,
	      ysize => 5,
	      device => $file,
	      @plot,
	      @plot2,
	    );

}




if ($opt{type} eq 'scatter'){
    
    my $all_select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
					     fields => [ "id", "mag_exp", "percent_not_tracking", "percent_bad_status" ],
					     where =>  { type => { '!=' => 'FID'},
							 kalman_tstart => { '>=' => $interval{tstart} },
							 kalman_tstop => { '<=' => $interval{tstop} },
						     },
					 });

    my $query = $all_select->get_select_string();

#    print "query is $query \n";
    
    my $sqlh= $handle->prepare($query);
    $sqlh->execute();
    my @x_mag;
    my @y_nt;
    my @y_ntbs;
    while( my $star = $sqlh->fetchrow_hashref()){
#	print Dumper $star;
	push @x_mag, $star->{mag_exp};
	push @y_nt, $star->{percent_not_tracking}/100.;
	push @y_ntbs, ($star->{percent_not_tracking}/100)+($star->{percent_bad_status}/100); 
    }


    my @label = ( 
		);

    my $mag_plot_start = $config{task}->{scatter}->{mag_plot_start};
    my $mag_plot_stop = $config{task}->{scatter}->{mag_plot_stop};

#    print "mag plot start $mag_plot_start \n";

    my @plot = ( panel => [1,1],
		 'x' => pdl(@x_mag),
		 'y' => pdl(@y_nt),
		 logy => 1,
		 lims => [$mag_plot_start, $mag_plot_stop, 0.0001, undef],
		 options => {center => 1},
		 charsize => {symbol => 0.7,
			      title => 2.0,
			      axis => 2.0,
			  },
		 toptitle => "Fraction not tracking",
		 xtitle => 'Star magnitude (mag)',
		 ytitle => 'Fraction',
		 @label,
		 plot => 'points',
		 'x' => [[ $mag_plot_start, $mag_plot_stop ]],
		 'y' => [[ (100-$BAD_PERCENT)/100., (100-$BAD_PERCENT)/100. ]],
		 color => { line => 'red' },
		 plot => 'line',
		 panel => [1,2],
		 'x' => pdl(@x_mag),
		 'y' => pdl(@y_ntbs),
		 logy => 1,
		 lims => [$mag_plot_start, $mag_plot_stop, 0.0001, undef],
		 options => {center => 1},
		 charsize => {symbol => 0.7,
			      title => 2.0,
			      axis => 2.0,
			  },
		 toptitle => "Fraction not tracking or image status != 0",
		 xtitle => 'Star magnitude (mag)',
		 ytitle => 'Fraction',
		 @label,
		 plot => 'points',
		 'x' => [[ $mag_plot_start, $mag_plot_stop ]],
		 'y' => [[ (100-$BAD_PERCENT)/100., (100-$BAD_PERCENT)/100. ]],
		 color => { line => 'red' },
		 plot => 'line',
	     );

    my $file = $config{task}->{scatter}->{plot_name} . "/vcps";
#
    pgs_plot( 
	      ny => 2,
	      xsize => 6,
	      ysize => 5,
	      device => $file,
	      @plot,
#	      @plot2,
	    );
#

}

##    $sqlh->finish;
##    $dbh->disconnect;
#
#

#    my $answer_ref = $all_select->run({ handle => $handle, type => 'array' });
    
#    for my $star (@
