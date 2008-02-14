package  Ska::StarStats::Report;

=pod

=head1 NAME

Ska::StarStats::Report - Make tables and plots for star statistics (acquisition and guide )

=head1 SYNOPSIS

 For acq stats:

 Ska::StarStats::Report->new({ task => 'acq_stat_reports',
                               config => \%config,
                               opt => \%opt,
                              })->standard_report();

 See files make_report.pl and report.yaml from the guide_stat_reports or acq_stat_reports
 projects for a quick look at the %config and %opt setup.

=head1 DESCRIPTION

Ska::StarStats::Report contains methods to create yaml summaries, html reports, and gif plots
of the data in the acquisition or guide star tables.  Selection of the relationships to summarize,
report, and plot is passed in options and configuration hashes.

=head1 EXPORT

None

=head1 METHODS

=cut




use strict;
use warnings;


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


use Class::MakeMethods::Standard::Hash( scalar => [ qw(
						       task
						       config
						       opt
						       dir
						       output_html
						       report_yaml
						       interval
						       counts
                                                       )                                                    ]

			
                                        );



 
sub new{

=pod

 * new(\%args) 

Creates a reporting object.

%args must have a "task" element of (at this time) 'acq_stat_reports' or 'guide_stat_reports' .

%args must also have a "config" element and an "opt" element, though they may be empty 
(course it isn't going to do much if they are).

=cut


    my $class = shift;
    my $self = {};
    bless $self, $class;

    my $arg_in = shift;
    for my $key (keys %{$arg_in}){
	$self->$key($arg_in->{$key});
    }
    unless (defined $self->task()){
	croak("Task type must be specified \n");
    }

    my $task = $self->task();
    my %dir;

# these paths should probably be in a separate config file, but it isn't likely that 
# we'll need a web test area for this type of project, so it can all end up in 
# /proj/sot/ska/www/ASPECT/${task} and be referenced from the web as such.

    my $SKA  = $ENV{SKA} || '/proj/sot/ska';
    $dir{SKA} = $SKA;
    $dir{SHARE} = "${SKA}/share/${task}";
    $dir{WEBDATA} = "${SKA}/www/ASPECT/${task}";
    $dir{SKADATA} = "${SKA}/data/${task}";
    $dir{BASEURL} = "http://cxc.harvard.edu/mta/ASPECT/${task}";

# If the report is not working in predefined mode, it is going to stick the output in 
# to the specified or current directory; the paths are set here

    if (defined $self->opt->{predefined}){
	$dir{URL} = $dir{BASEURL} . "/" . $self->opt->{year} . "/" . $self->opt->{id};
    }
    else{
	$dir{URL} = ".";
    }


    my %opt = %{$self->opt};
    my $save_prefix = qq{};
    my $data_save_prefix;

    if (defined $opt{save_path}){
	if (defined $opt{predefined}){
	    # watch the order here... don't extend save_path before data_save_path
	    $dir{DATA_SAVE_PATH} = $dir{SKADATA} . "/" . $opt{save_path};
	    $dir{SAVE_PATH} = $dir{WEBDATA} . "/" . $opt{save_path};
	    
	}
	else{
	    $dir{SAVE_PATH} = $opt{save_path} . "/";
	}
    }
    else{
	$dir{SAVE_PATH} = ".";
    }
    
    if (not defined $dir{DATA_SAVE_PATH}){
	$dir{DATA_SAVE_PATH} = $dir{SAVE_PATH};
    }


# use Data::Dumper;
# print Dumper %dir;


    $self->dir(\%dir);

    return $self;
}
   

sub standard_report{

=pod


 * standard_report()

Calls the methods to make plots and reports


=cut

    my $self = shift;

    eval{
	$self->text_data();
    };
    if($@){
	if ("$@" =~ /No stars/){
	    print "No Stars during this interval \n";
	}
	else{
	    print "$@ \n";
	}
    }
    else{
       $self->make_plots();
	
    }
    return $self;
}


sub text_data{
    my $self = shift;

    my %opt = %{$self->opt()};

    # Define the two key intervals... one for everything thus far and one for the
    # duration of interest for the report

    my %mission_interval = %{define_interval({ tstart => $opt{calc_rate_tstart},
					       tstop => $opt{calc_rate_tstop}}) };
    
    my %report_interval = %{define_interval({ tstart => $opt{tstart},
					      tstop => $opt{tstop} })};


    my %interval = ( mission => \%mission_interval,
		     report => \%report_interval );

    $self->interval(\%interval);


    my %counts = %{$self->get_counts()};
    
    #if there aren't any stars, let's stop fooling around
    if ($counts{report}->{all_stars} == 0){
	croak("No stars during this interval");
    }

    # the 'expected' rates and such don't follow the same format as the
    # counts for an interval, so we'll store them on their own and
    # then shove them into %counts with that name

    my %expected = %{$self->calc_expected(\%counts)};

    $expected{name} = 'expected';

    $counts{expected} = \%expected;

    my %prob = %{$self->calc_prob(\%counts)};

    # Add the probabilities to the counts hash
    for my $key (keys %prob){
	$counts{report}->{$key} = $prob{$key};
    }

    $self->counts(\%counts);

    # Make a main table of all of the counts by rate that we've retrieved
    $self->make_table('main');

    # If there are any areas (like the tail end of the magnitude range for guide stats)
    # that deserve further examination, that is in the {loop} config hash.
    # make any tables there.
    my @loops = @{$self->config->{task}->{data}->{loops}};
    for my $loop (@loops){
	$self->make_table('loop', $loop->{name});
    }
    
    # What are the real report times?
    my $ctime_start = Chandra::Time->new( $report_interval{tstart} );
    my $ctime_stop = Chandra::Time->new( $report_interval{tstop} );

    my %report;

    $report{date_start} = $ctime_start->date();
    $report{date_stop} = $ctime_stop->date();
    
    
    $report{human_date_start} = time2str("%d-%b-%Y", $ctime_start->unix(), '+0000');
    $report{human_date_stop} =  time2str("%d-%b-%Y", $ctime_stop->unix(), '+0000' );

    # If this is a predefined report, like one for a month, it has a title passed
    # as an option
    $report{title} = qq{};
    if (defined $self->opt->{title}){
	$report{title} = $self->opt->{title};
    }

    # copy report elements to output_html hash and store for yaml
    my %report_yaml = %report;
    my %output_html = %{$self->output_html()};
    for my $key (keys %report){
	$output_html{$key} = $report{$key};
    }
    for my $key (keys %counts){
	$report_yaml{$key} = $counts{$key};
    }
    $self->report_yaml(\%report_yaml);
    $self->output_html(\%output_html);

    for my $plot (keys %{$self->config->{task}->{plots}}){
	my $url_dir = $self->dir->{URL};
	my $img_file = $self->config->{task}->{plots}->{$plot}->{plot_name};
	$output_html{"$plot" . "_plot"} = qq{<IMG SRC="${url_dir}/${img_file}">};
    }

    # Write out the text of everything to files
    $self->write_reports();


}


sub make_star_table{
    # this a generic method to make html tables of stars
    # this is called by the other table making scripts when stars meet criteria


    my $self = shift;
    my $list = qq{};
    my $table_id = shift;
    my $loop_args = shift;

    my %config = %{$self->config};

    return $list unless (defined $table_id);

    my %where;
    my $rate_info;
    if (defined $loop_args){
	%where = %{$loop_args->{loop_data}->{sql_where}};
	$rate_info = $loop_args->{rate_cfg};
    }
    else{
	%where = %{$self->counts->{report}->{sql_where}};    
    	for my $rate_ref (@{$config{task}->{data}->{rates}}){
#	    unless ($rate_ref->{rate} eq $table_id){
#		print "$table_id does not match \n";
#	    }
	    next unless ( $rate_ref->{name} eq $table_id );
	    $rate_info = $rate_ref;
	    
	}
	
    }
    
    # Build a query to get the stars

    my @field_list = @{$config{task}->{data}->{lookup_table_fmt}->{fields}};;
    my @format_list =  @{$config{task}->{data}->{lookup_table_fmt}->{field_fmt}};
    my $select = Ska::SQL::Select->new({ table => $config{task}->{db}->{table},
					 fields => \@field_list,
					 where => \%where,
					 order => $config{task}->{data}->{lookup_table_fmt}->{order},
				     });


    # make a query to get the stars that meed the criteria for this table
    my %make_select = %{$rate_info};
    if (defined $make_select{operator}){
	$select->add_where({ $make_select{field} => { $make_select{operator} => $make_select{value} }});
    }
    else{
	$select->add_where({ $make_select{field} => $make_select{value} });
    }
    

    my $handle = sql_connect( $config{task}->{db}->{connect_info} );
    
    my $answer_list = $select->run({ handle => $handle, type => 'array' });
    
    $handle->disconnect();


#    # do trivial switch on fields if defined as select "bob as sam"
    for my $idx (0 .. $#field_list){
	my $cfg_field = $field_list[$idx];
	if ($cfg_field =~ /\sas\s(\S*)/){
	    $field_list[$idx] = $1;
	}
    }

    
    if (scalar(@{$answer_list})){
	
	$list .= qq{<TABLE BORDER=1>};
	$list .= qq{<TR><TH>};
	$list .= join("</TH><TH>", @field_list);
	$list .= qq{</TH></TR>};
	
	my $count = 0;
	for my $starref (@{$answer_list}){
	    $count++;
	    if ($count > $config{task}->{limit_bad_list}){
		my $colspan = scalar(@field_list);
		$list .= "<TR><TD COLSPAN=$colspan> Stars excluded over limit </TD></TR>\n";
		last;
	    }
	    my $id = ( defined $starref->{id} ) ? $starref->{id} : qq{};
	    for my $key_idx (0 ... $#field_list){
		my $key = $field_list[$key_idx];
		my $value = (defined $starref->{$key}) ? $starref->{$key} : qq{};
		if ( defined $config{task}->{cgi_links}->{$key} ){
		    my $url = $config{task}->{cgi_links}->{$key}->{url};
		    my $get = $config{task}->{cgi_links}->{$key}->{get};
		    $get =~ s/%VALUE%/$value/g;
		    $list .= sprintf("<TD ALIGN=\"right\"><A HREF=\"%s\%s;\">",
				     $url, $get);
		    $list .= sprintf( $format_list[$key_idx], $value );
		    $list .= qq{ </A></TD> };
	
		    next;
		}
		my $format = $format_list[$key_idx];
		if (not defined $starref->{$key}){
		    $list .= qq{ <TD></TD> };
		}
		else{
		    $list .= sprintf("<TD ALIGN=\"right\">$format</TD>", $starref->{$key});
		}
		
		
	    }

	    $list .= qq{</TR> \n};

	}
	
    }


    my $label = "${table_id}_stars_list";
    my %output = ( $label => $list );

    if (not defined $self->output_html){
	$self->output_html(\%output);
    }
    else{
	my %exist_output = %{$self->output_html()};
	for my $key (keys %output){
	    $exist_output{$key} = $output{$key};
	}
	$self->output_html(\%exist_output); # which is probably not necessary
    }


    return $list;
    

}



    

sub calc_prob{
    # given the actual and expected counts for a set of criteria,
    # find the Poisson probability of the rate being less than or greater
    # than the actual rate

    my $self = shift;
    my $counts = shift;
    my $actual = $counts->{report};
    my $expected = $counts->{expected};

    my %prob;

    for my $rate_ref ( @{$self->config->{task}->{data}->{rates}} ){
	my $rate = $rate_ref->{name};
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
    # Multiply the number of stars for the interval by the expected rate 
    # of the event (from the all mission data)

    my $self = shift;
    my $counts = shift;
    my $mission = $counts->{mission};
    my $actual = $counts->{report};

    my %expected;

    my $n_stars = $actual->{all_stars};

    for my $rate_ref ( @{$self->config()->{task}->{data}->{rates}} ){
	my $rate = $rate_ref->{name};
	if (defined $mission->{"${rate}_rate"}){
	    $expected{"${rate}_rate"} = $mission->{"${rate}_rate"};
	    $expected{"${rate}_stars"} = $n_stars * $mission->{"${rate}_rate"};
	}
    }

    return \%expected;

}

sub make_table{
    # make an HTML table of all of the requested star rates
    # if we are in making a loop table, use reduced reporting (no probabilities)

    my $self = shift;
    my $type = shift;
    my $loop = shift;



    my $config = $self->config();
 
    my $expected = $self->counts->{expected};
    my $actual = $self->counts->{report};

    my $table = qq{ <TABLE BORDER=1>\n };

    my @fields = qw( name all_stars );
    my @colspan = qw( 1 1 );
    for my $rate_ref ( @{$config->{task}->{data}->{rates}} ){
	my $rate = $rate_ref->{name};
	push @fields, "${rate}_stars";
  	push @fields, "${rate}_rate";
	if ($type eq 'main'){
	    push @colspan, 4;
	    push @colspan, 2;
	}
	if ($type eq 'loop'){
	    push @colspan, 1;
	    push @colspan, 1;
	}
    }


    # Top Header Row
    $table .= qq{ <TR><TH colspan=2></TH> };
    for my $rate_ref ( @{$config->{task}->{data}->{rates}} ){
	my $rate = $rate_ref->{name};
	if ($type eq 'main'){
	    $table .= qq{ <TH colspan=6>$rate</TH> };
	}
	if ($type eq 'loop'){
	     $table .= qq{ <TH colspan=2>$rate</TH> };
	 }
    }
    $table .= qq{ </TR> \n };

    # Grouping Header Row
    $table .= qq{ <TR><TH></TH> };
    if ($type eq 'main'){
	$table .= qq{ <TH></TH> };
    }
    if ($type eq 'loop'){
	$table .= qq{ <TH>N Stars</TH> };
    }
    

    for my $rate_ref ( @{$config->{task}->{data}->{rates}} ){
	if ($type eq 'main'){
	    $table .= qq{ <TH colspan=4>stars</TH> };
	    $table .= qq{ <TH colspan=2>rate</TH> };
	}
	if ($type eq 'loop'){
	    $table .= qq{ <TH colspan=1>stars</TH> };
	    $table .= qq{ <TH colspan=1>rate</TH> };
	}

    }
    $table .= qq{ </TR> \n };

    if ($type eq 'main'){

	# Probability Header Row
	$table .= qq{ <TR><TH></TH><TH>n stars</TH> };
        for my $rate ( @{$config->{task}->{data}->{rates}}){
	    for my $entry_ref (@{$config->{task}->{data}->{main_table_fmt}}){
		my $label = $entry_ref->{label};
		$table .= qq{ <TH> $label </TH> };
	    }
	}
	$table .= qq{ </TR> \n };
    }

    $table .= "\n";


# Then the actual data Row or rows
    
    my $table_data;
    if ($type eq 'main'){
	$table_data = $self->make_table_rows($type);
    }
    else{
	if (not defined $loop){
	    croak("No way to save loop date; no name defined \n");
	}
	$table_data = $self->make_table_rows($type, $loop);
	$type = $loop . "_" . $type;
    }

    $table .= $table_data;

    my %output = ( "${type}_table" => $table );

    if (not defined $self->output_html){
	$self->output_html(\%output);
    }
    else{
	my %exist_output = %{$self->output_html()};
	for my $key (keys %output){
	    $exist_output{$key} = $output{$key};
	}
	$self->output_html(\%exist_output); # which is probably not necessary
    }
    
}


sub make_table_rows{
    # "Linkify" the data elements as needed 

    my $self = shift;
    my $type = shift;
    my $loopname = shift;
    my $table;
    my @data_rows = @{$self->get_data_rows($type, $loopname)};
    for my $row (@data_rows){
	$table .= qq{ <TR> };
	for my $entry (@{$row}){
	    my $value = $entry->{text};
	    if (defined $entry->{link}){
		my $link = $entry->{link};
		my $url = $self->dir->{URL};

		$table .= qq{ <TD><A HREF="${url}/${link}">${value}</A></TD };
	    }
	    else{
		$table .= qq{ <TD>${value}</TD> };
	    }
	}
	$table .= qq{ </TR> \n };
    }

    return $table;
}


sub get_data_rows{
    # Format the rate data as needed and figure out links for stuff like agasc_id and obsid

    my $self = shift;
    my $type = shift;
    my $loopname = shift;
    my @rows;
    if ($type eq 'main'){
	my %counts = %{$self->counts};
	my @row = ( { text => 'report' } );
	push @row, { text => $counts{report}->{all_stars} };
	for my $rate_ref (@{$self->config->{task}->{data}->{rates}}){
	    my $rate = $rate_ref->{name};
#	    print "rate is $rate \n";
	    for my $field_ref (@{$self->config->{task}->{data}->{main_table_fmt}}){
		my ( $source, $value_label ) = ($field_ref->{source}, $field_ref->{value});
		my $fmt = $field_ref->{fmt};
#		print "$source $value_label \n";
		my $value = sprintf( "$fmt", $self->counts->{$source}->{"${rate}_${value_label}"});
		if (($source eq 'report') and ($value_label eq 'stars') and ($value > 0)){
		    my $link = "${rate}_stars_list.html";
		    $self->make_star_table("${rate}");
#		    $output{"${rate}_stars"} = $self->make_star_table("${rate}_stars");
		    push @row, { text => $value,
				 link => $link };
		}
		else{
		    push @row, { text => $value };
		}
	    }

	}
	push @rows, \@row;
	return \@rows;	
    }
    if ($type eq 'loop'){

	my $which_loop;
	for my $loopidx (0 ... scalar(@{$self->config->{task}->{data}->{loops}})-1 ){
	    my $loop_cfg = $self->config->{task}->{data}->{loops}->[$loopidx];
	    if ($loop_cfg->{name} eq $loopname ){
		$which_loop = $loopidx;
		last;
	    }
	}
	for my $loop_data_ref (@{$self->{counts}->{report}->{loops}->[$which_loop]}){
	    my @row = ( { text => sprintf( $loop_data_ref->{start} . " - " . $loop_data_ref->{stop} )},
			{ text => sprintf( $loop_data_ref->{all_stars} )});
	    for my $rate_ref (@{$self->config->{task}->{data}->{rates}}){
	    my $rate = $rate_ref->{name};
		for my $row_entry (@{$self->config->{task}->{data}->{loop_table_fmt}}){
		    my ( $source, $value_label ) = ($row_entry->{source}, $row_entry->{value});
		    my $fmt = $row_entry->{fmt};
#		print "$source $value_label \n";
		    my $value = sprintf( "$fmt", $loop_data_ref->{"${rate}_${value_label}"});
		    if (($source eq 'report') and ($value_label eq 'stars') and ($value > 0)){
			my $loop_id = $loop_data_ref->{name};
			my $custom_rate = "${rate}_${loop_id}";
			$custom_rate =~ s/\./p/g;
			my $link = "${custom_rate}_stars_list.html";
			$self->make_star_table("${custom_rate}", { rate_cfg => $rate_ref, loop_data => $loop_data_ref });
   			push @row, { text => $value,
				     link => $link };

		    }
		    else{
			push @row, { text => $value };
		    }
		    
		    
		}

	    
		}

		push @rows, \@row;
	    }


	}
	return \@rows;
    }


sub write_reports{
    # write out the text data

    my $self = shift;
    my %dir = %{$self->dir()};

#    use Data::Dumper;
#    print Dumper %dir;

##    print "destfile is $destfile \n";
    unless ($self->opt->{dryrun}){
#	print "in writing section \n;";

	if (defined $dir{SAVE_PATH}){
	    mkpath( $dir{SAVE_PATH}, 1 );
	}
	if (defined $dir{DATA_SAVE_PATH}){
	    mkpath( $dir{DATA_SAVE_PATH}, 1);
	}
	
	my $index_infile = $self->config->{task}->{templates}->{index_file};
	if ($self->opt->{predefined}){
	    $index_infile = $self->config->{task}->{templates}->{predefined_index_file};
	}



	if (-e "$dir{SHARE}/${index_infile}"){
#	if (-e "${index_infile}"){
	    my $index = io("$dir{SHARE}/${index_infile}")->slurp;
#	    my $index = io("${index_infile}")->slurp;
	    io("$dir{SAVE_PATH}/index.html")->print($index);
	}
	else{
	    croak("Error, no template index file defined \n");
	}
	# Each of the HTML pieces gets its own file
	for my $html_piece (keys %{$self->output_html()}){
	    
	    if ($html_piece =~ /list$/){
		io("$dir{SAVE_PATH}/${html_piece}.html")->print($self->output_html->{$html_piece});
	    }
	    else{
		io("$dir{SAVE_PATH}/${html_piece}.htm")->print($self->output_html->{$html_piece});
	    }
	}

	my $yamlfile = $self->config->{task}->{templates}->{report_yaml_file};

	if (defined $yamlfile){
	    io("$dir{DATA_SAVE_PATH}/${yamlfile}")->print(Dump(\%{$self->report_yaml()}));
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

#
#
sub get_counts{

    my $self = shift;


    my %result;

    my %time_ranges = ( mission => $self->interval()->{mission},
			report => $self->interval()->{report});

#    my %config = %{$arg_in->{config}};
#
    my $handle = sql_connect( $self->config()->{task}->{db}->{connect_info} );

    my $exclude_bad_obsid = 'not in (select obsid from expected_bad_obsids)';    

    for my $select_range (keys %time_ranges ){

#	print "for my $select_range \n";

	my $time_range = $time_ranges{$select_range};
	my %result_range = ( name => $select_range,
			     tstart => $time_range->{tstart},
			     tstop => $time_range->{tstop},
			     );
	my $time_start_field = $self->config->{task}->{db}->{time_start_field};
	my $time_stop_field = $self->config->{task}->{db}->{time_stop_field};
	
	my %time_where;
	if ("$time_start_field" eq "$time_stop_field"){
	    %time_where = ( "$time_start_field" => { '>=' => $time_range->{tstart} ,
						     '<=' => $time_range->{tstop} } );
	}
	else{
	    %time_where = (  "$time_start_field" => { '>=' => $time_range->{tstart} },
			     "$time_stop_field"  => { '<=' => $time_range->{tstop} },
			     );
	}
	

	my %where = %time_where;
	$where{obsid} = \$exclude_bad_obsid;


	
	my $default_select = Ska::SQL::Select->new({ table => $self->config->{task}->{db}->{table},
						     fields => [ $self->config->{task}->{data}->{count_field} . " as n" ],
						     where => \%where,
						 });
	
#	print $default_select->get_select_string(), "\n";

	my $all_stars =  $default_select->run({handle => $handle, type => 'array' })->[0]->{n};
	$result_range{all_stars} = $all_stars;
	$result_range{"sql_where"} = \%where;
	
	for my $rate_ref ( @{$self->config->{task}->{data}->{rates}} ){

	    
	    my $rate_type = $rate_ref->{name};
	   
#	    my %make_select = %{$self->config->{task}->{data}->{rates}->{$rate_type}};
	    my %make_select = %{$rate_ref};
	    
	    if (defined $make_select{operator}){
		$default_select->add_where({ $make_select{field} => { $make_select{operator} => $make_select{value} }});
	    }
	    else{
		$default_select->add_where({ $make_select{field} => $make_select{value} });
	    }

#	    print $default_select->get_select_string(), "\n";
	    
	    my $n_stars =  $default_select->run({handle => $handle, type => 'array'})->[0]->{n};


	    $result_range{"${rate_type}_stars"} = $n_stars;

	    $result_range{"${rate_type}_rate"} = $all_stars != 0 ? ( $n_stars / $all_stars) : 0;

	    
	    # reset where
	    $default_select->where(\%where);

	}

	if (defined $self->config->{task}->{data}->{loops}){

	    my @all_loop;
	    for my $loop_def (@{$self->config->{task}->{data}->{loops}}){
		my %loop_cfg = %{$loop_def};
		my @loop;
#	    print Dumper $mag_zoom_ref;
		for ( my $chunk = $loop_cfg{start}; $chunk < $loop_cfg{stop}; $chunk += $loop_cfg{bin} ){
#		my $bin = $mag_zoom_ref->{mag_bin};
#		    print "mag is $mag \n";
		    my %pass_result;
		    $pass_result{start} = $chunk;
		    $pass_result{stop} = ($chunk + $loop_cfg{bin});
		    $pass_result{bin_over} = $loop_cfg{bin_over};
		    
		    # copy the where
		    my %loop_where;
		    for my $key (keys %where){
			$loop_where{$key} = $where{$key};
		    }
		    $loop_where{$loop_cfg{bin_over}} = { '>=' => $chunk, 
							 '<'  => $chunk + $loop_cfg{bin} };
		    
		    $pass_result{"sql_where"} = \%loop_where;
#		print "$mag \n";
#		print Dumper \%where;
		    $default_select->where(\%loop_where);
		    

		    my $pass_all_stars =  $default_select->run({handle => $handle, type => 'array' })->[0]->{n};
		    $pass_result{all_stars} = $pass_all_stars;
#		print Dumper %mag_result;
#
		    for my $rate_ref ( @{$self->config->{task}->{data}->{rates}} ){
			
			my $rate_type = $rate_ref->{name};
			my $n_stars;
			if ($pass_all_stars == 0){
			    $n_stars = 0;
			}
			else{
			    my %make_select = %{$rate_ref};

			    
			    if (defined $make_select{operator}){
				$default_select->add_where({ $make_select{field} => { $make_select{operator} => $make_select{value} }});
			    }
			    else{
				$default_select->add_where({ $make_select{field} => $make_select{value} });
			    }
			    
#		    print $default_select->get_select_string(), "\n";
			    
			    $n_stars =  $default_select->run({handle => $handle, type => 'array'})->[0]->{n};
			    
			    
			}
#		    print "n is $n_stars \n";
			
			
			
			$pass_result{"${rate_type}_stars"} = $n_stars;
			
			$pass_result{"${rate_type}_rate"} = $pass_all_stars != 0 ? ( $n_stars / $pass_all_stars ) : 0;
			
			$default_select->where(\%loop_where);
		    }
		    
#
#		print Dumper %mag_result;
		    $pass_result{name} = $chunk;

		    push @loop, \%pass_result;
		}
		
		push @all_loop, \@loop;
	    }		

	    $result_range{loops} = \@all_loop;


	}


	$result{$select_range} = \%result_range;

    }

    return \%result;
}
#
#
#
#
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
    my $self = shift;
   
#    my $arg_in = shift;
    my %config = %{$self->config()};
    my %opt = %{$self->opt()};

    my $time_start_field = $config{task}->{db}->{time_start_field};
    my $time_stop_field = $config{task}->{db}->{time_stop_field};

    my %report_interval = %{define_interval({ tstart => $opt{tstart},
					      tstop => $opt{tstop}}) };
    my %mission_interval = %{define_interval({ tstart => $opt{calc_rate_tstart},
						tstop => $opt{calc_rate_tstop}})};
    
#    my $BAD_PERCENT = $config{task}->{bad_telem_threshold};
    
    $ENV{PGPLOT_BACKGROUND} = 'white';
    $ENV{PGPLOT_FOREGROUND} = 'black';
    
    my $handle = sql_connect( $config{task}->{db}->{connect_info} );
    

    my $save_prefix = qq{};
#    if (defined $opt{save_string}){
#	$save_prefix = $opt{save_string};
#    }
    if (defined $opt{save_path}){
	if (defined $opt{predefined}){
	    $save_prefix .= $self->dir->{WEBDATA} . "/" . $opt{save_path} . "/";
	    $opt{save_path} = $self->dir->{WEBDATA} . "/" . $opt{save_path};
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
	my $plot_padlog = 0;

	# make the silly array/hash that pgs_plot
	if ( defined $plotcfg{pgs_plot}){
	    for my $pgs_elem (@{$plotcfg{pgs_plot}}){
		for my $key (keys %{$pgs_elem}){ 
		    push @plot_array, $key => $pgs_elem->{$key};
		    if ($key eq 'logy'){
			$plot_padlog = $pgs_elem->{$key};
		    }
		}
						 
	    }

	}

	if (defined $plotcfg{pad_log}){
	    unless ($plotcfg{pad_log}){
		$plot_padlog = 0;
	    }
	}

	my $table = ( defined $plotcfg{table} ) ? $plotcfg{table} : $config{task}->{db}->{table};
	

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

	    my $top_level_bin_type;
	    if (defined $plotcfg{bin_over}){
		$top_level_bin_type = $plotcfg{bin_over};
	    }
	    
	    my $start = $plotcfg{start};
	    my $stop =  $plotcfg{stop};
	    my $bin_size =  $plotcfg{bin};
	    
	    
	    my @red;
	    my @black;
	    my @data_bin;
	    
	    for ( my $bin = $start; $bin < $stop; $bin += $bin_size ){
		
		push @data_bin, $bin;
		
		if (defined $plotcfg{black}){

		    my %interval = %report_interval;
		    if (defined $plotcfg{interval}){
			if ( $plotcfg{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }
		    if (defined $plotcfg{black}->{interval}){
			if ($plotcfg{black}->{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }

		    my $bin_type = (defined $plotcfg{black}->{bin_over}) ? $plotcfg{black}->{bin_over} : $top_level_bin_type;
		    
		    my %where = (defined $plotcfg{black}->{where} ) ? %{$plotcfg{black}->{where}} : ();
		    my %time_where;
		    if ("$time_start_field" eq "$time_stop_field"){
			%time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
								 '<=' => $interval{tstop} } );
		    }
		    else{
			%time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
					 "$time_stop_field"  => { '<=' => $interval{tstop} },
					 );
		    }

		    my $black_select = Ska::SQL::Select->new({ table => $table,
							      fields => $plotcfg{black}->{fields},
							       where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
									 %where,
									 %time_where,
								     },						
							  });
		    
#		    print $black_select->get_select_string(), "\n";
		    my $black_ref = $black_select->run({ handle => $handle, type => 'array' });
		    my $black_scale;
		    if ( defined $plotcfg{black}->{scale} ){
			if ( $plotcfg{black}->{scale} =~ /fraction/){
			    my $black_all_select = Ska::SQL::Select->new({ table => $table,
									   fields => $plotcfg{black}->{fields},
									   where =>  { 
									       %where,
									       %time_where,
									   },						
								       });
			    my $black_all_ref = $black_all_select->run({ handle => $handle, type => 'array' });
			    my $black_all_cnt = $black_all_ref->[0]->{black};
			    if ($black_all_cnt > 0){
				$black_scale = 1/($black_all_cnt) ;
			    }
			}
			else{
			    $black_scale = $plotcfg{black}->{scale};
			}
				
		    }
		    if (not defined $black_scale){
			$black_scale = 1;
		    }

		    push @black, $black_ref->[0]->{black} * $black_scale ;
		    
#		    print "$bin black ", $black_ref->[0]->{black}, "\n";
		    %interval = %{define_interval({ tstart => $opt{tstart},
						    tstop => $opt{tstop}}) };


		}
		if (defined $plotcfg{red}){
		    my %interval = %report_interval;
		    if (defined $plotcfg{interval}){
			if ( $plotcfg{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }
		    if (defined $plotcfg{red}->{interval}){
			if ($plotcfg{red}->{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }


		    my $bin_type = (defined $plotcfg{red}->{bin_over}) ? $plotcfg{red}->{bin_over} : $top_level_bin_type;
		    my %where = (defined $plotcfg{red}->{where} ) ? %{$plotcfg{red}->{where}} : ();
		    my %time_where;
		    if ("$time_start_field" eq "$time_stop_field"){
			%time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
								 '<=' => $interval{tstop} } );
		    }
		    else{
			%time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
					 "$time_stop_field"  => { '<=' => $interval{tstop} },
					 );
		    }


		    my $red_select = Ska::SQL::Select->new({ table => $table,
							     fields => $plotcfg{red}->{fields},
							     where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
									%where,
									%time_where,
									
								    },						
							 });
		    
#		    print Dumper $red_select;
		    my $red_ref = $red_select->run({ handle => $handle, type => 'array' });
		    my $red_scale;
		    if ( defined $plotcfg{red}->{scale} ){
			if ( $plotcfg{red}->{scale} =~ /fraction/){
			    my $red_all_select = Ska::SQL::Select->new({ table => $table,
									 fields => $plotcfg{red}->{fields},
									 where =>  { 
									     %where,
									     %time_where,
									 },						
								     });
			    my $red_all_ref = $red_all_select->run({ handle => $handle, type => 'array' });
			    my $red_all_cnt = $red_all_ref->[0]->{red};
			    if ($red_all_cnt > 0){
				$red_scale = 1/($red_all_cnt) ;
			    }
			}
			else{
			    $red_scale = $plotcfg{red}->{scale};
			}
			
		    }
		    if (not defined $red_scale){
			$red_scale = 1;
		    }

		    push @red, $red_ref->[0]->{red} * $red_scale ;
#		    print "$bin red ", $red_ref->[0]->{red}, "\n";
		}
		
		
	    }

#	    print Dumper @data_bin;
#	    print Dumper @black;
#	    print Dumper @red_x100;


	    # find min non-zero value
	    if (scalar(@black)){
		my $black_pdl = pdl(@black);
		my $min_non_zero = $black_pdl->( which( $black_pdl > 0) )->min();
		my $y_black =  $plot_padlog ? $black_pdl + ($min_non_zero/10.) : $black_pdl;
		
		push @plot_array,   
		'x' => pdl(@data_bin),
		'y' => $y_black,
		options => {center => 1},
		charsize => {symbol => 0.7,
			     title => 2.0,
			     axis => 2.0,
			 },
		plot => 'bin',
		;
		
		if (scalar(@red)){
		    my $red_pdl = pdl(@red);
		    my $y_red = $plot_padlog ? $red_pdl + ($min_non_zero/10.) : $red_pdl;
		    
		    
		    push @plot_array,
		    'x' => pdl(@data_bin)+0.01,
		    'y' => $y_red,
		    options => {center => 1},
		    charsize => {symbol => 0.7,
				 title => 2.0,
				 axis => 2.0,
			     },
		    color => { line => 'red' },
		    plot => 'bin',
		    ;
		    
		}
	    }


	}
    
	    
	  #	print scalar(@mag_bin), ":", scalar(@black_track), ":", scalar(@red_track_x100), ":", scalar(@red_color_x100), ":", scalar(@black_color), "\n";
	    
	    # if anything is defined in the config file, use it
	    
	    
	if ($plot =~ /scatter/){
	    my %interval = %report_interval;
	    if (defined $plotcfg{interval}){
		if ( $plotcfg{interval} eq 'mission'){
		    %interval = %mission_interval;
		}
	    }

		my %where = (defined $plotcfg{where}) ? %{$plotcfg{where}} : ();
#		print "$plot is scatter \n";
		my %time_where;
		if ("$time_start_field" eq "$time_stop_field"){
		    %time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
							     '<=' => $interval{tstop} } );
		}
		else{
		    %time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
				     "$time_stop_field"  => { '<=' => $interval{tstop} },
				     );
		}


		my $all_select = Ska::SQL::Select->new({ table => $table,
							 fields => [ "$plotcfg{x} as x", "$plotcfg{y} as y"],
							 where => { %where,
								    %time_where,
								 },
						     });
# { type => { '!=' => 'FID'},
		
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
#		 'y' => [[ ($RED_PERCENT)/100., ($RED_PERCENT)/100. ]],
#		 color => { line => 'red' },
#		 plot => 'line',

		# find min non-zero value
		my $black_pdl = pdl(@y);
		my $min_non_zero = $black_pdl->( which( $black_pdl > 0) )->min();
		my $y = $plot_padlog ? $black_pdl + ($min_non_zero/10.) : $black_pdl;
		
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

	if ( $plot =~ /pointhist/){

	    my $top_level_bin_type;
	    if (defined $plotcfg{bin_over}){
		$top_level_bin_type = $plotcfg{bin_over};
	    }
	    
	    my $start = $plotcfg{start};
	    my $stop =  $plotcfg{stop};
	    my $bin_size =  $plotcfg{bin};
	    
	    
	    my @red;
	    my @red_m;
	    my @red_p;

	    my @black;
	    my @black_m;
	    my @black_p;
	    
	    my @data_bin;
	    
	    for ( my $bin = $start; $bin < $stop; $bin += $bin_size ){
		
		push @data_bin, $bin;
		
		if (defined $plotcfg{black}){

		    my %interval = %report_interval;
		    if (defined $plotcfg{interval}){
			if ( $plotcfg{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }
		    if (defined $plotcfg{black}->{interval}){
			if ($plotcfg{black}->{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }

		    my $bin_type = (defined $plotcfg{black}->{bin_over}) ? $plotcfg{black}->{bin_over} : $top_level_bin_type;
		    
		    my %where = (defined $plotcfg{black}->{where} ) ? %{$plotcfg{black}->{where}} : ();
		    my %time_where;

		    if ("$time_start_field" eq "$time_stop_field"){
			%time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
								 '<=' => $interval{tstop} } );
		    }
		    else{
			%time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
					 "$time_stop_field"  => { '<=' => $interval{tstop} },
					 );
		    }

		    my $black_select = Ska::SQL::Select->new({ table => $table,
							      fields => $plotcfg{black}->{fields},
							       where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
									  %where,
									  %time_where,
								      },						
							   });
		    
#		    print $black_select->get_select_string(), "\n";
		    my $black_ref = $black_select->run({ handle => $handle, type => 'array' });
		    
		    if (defined $plotcfg{black_all}){
			my %all_interval = %report_interval;
			if (defined $plotcfg{interval}){
			    if ( $plotcfg{interval} eq 'mission'){
				%all_interval = %mission_interval;
			    }
			}
			if (defined $plotcfg{black}->{interval}){
			    if ($plotcfg{black}->{interval} eq 'mission'){
				%all_interval = %mission_interval;
			    }
			}
			
			
			$bin_type = (defined $plotcfg{black_all}->{bin_over}) ? $plotcfg{black_all}->{bin_over} : $top_level_bin_type;
			
			%where = (defined $plotcfg{black_all}->{where} ) ? %{$plotcfg{black_all}->{where}} : ();
			

			if ("$time_start_field" eq "$time_stop_field"){
			    %time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
								     '<=' => $interval{tstop} } );
			}
			else{
			    %time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
					     "$time_stop_field"  => { '<=' => $interval{tstop} },
					     );
			}

			my $black_all_select = Ska::SQL::Select->new({ table => $table,
								       fields => $plotcfg{black_all}->{fields},
								       where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
										  %where,
										  %time_where,
									      },						
								   });
		    
#		    print $black_select->get_select_string(), "\n";
			my $black_allref = $black_all_select->run({ handle => $handle, type => 'array' });

			my $black_cnt = $black_ref->[0]->{black};
			my $black_all_cnt = $black_allref->[0]->{black_all};

			my $ratio = ( $black_all_cnt > 0 ) ? $black_cnt/$black_all_cnt : 0;
			my $err_low_lim = ($black_all_cnt > 0) ? ((sqrt($black_cnt)/$black_all_cnt) * 1) : 0;
			push @black_m, -($err_low_lim);
        # set the upper limit on the error bar to 100% (by setting the size of the bar to 100-value if
        # the bar is going to end up over 100)
			my $err_high_lim = ($err_low_lim + $ratio) < 1 ? $err_low_lim : 1 - $ratio;
			push @black_p, $err_high_lim;
			push @black, $ratio;
#			print "black is $ratio \n";

		    }
		    else{
			push @black, $black_ref->[0]->{black};
			push @black_m, 0;
			push @black_p, 0;
		    }
#		    print "$bin black ", $black_ref->[0]->{black}, "\n";

		}
		if (defined $plotcfg{red}){
		    my %interval = %report_interval;
		    if (defined $plotcfg{interval}){
			if ( $plotcfg{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }
		    if (defined $plotcfg{red}->{interval}){
			if ($plotcfg{red}->{interval} eq 'mission'){
			    %interval = %mission_interval;
			}
		    }


		    my $bin_type = (defined $plotcfg{red}->{bin_over}) ? $plotcfg{red}->{bin_over} : $top_level_bin_type;
		    my %where = (defined $plotcfg{red}->{where} ) ? %{$plotcfg{red}->{where}} : ();
		    my %time_where;
		    if ("$time_start_field" eq "$time_stop_field"){
			%time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
								 '<=' => $interval{tstop} } );
		    }
		    else{
			%time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
					 "$time_stop_field"  => { '<=' => $interval{tstop} },
					 );
		    }


		    my $red_select = Ska::SQL::Select->new({ table => $table,
							     fields => $plotcfg{red}->{fields},
							     where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
									%where,
									%time_where,
									
								    },						
							 });
		    
#		    print Dumper $red_select;
		    my $red_ref = $red_select->run({ handle => $handle, type => 'array' });
		    my $red_scale = ( defined $plotcfg{red}->{scale} ) ? $plotcfg{red}->{scale} : 1;
		
		
		    if (defined $plotcfg{red_all}){
			my %all_interval = %report_interval;
			if (defined $plotcfg{interval}){
			    if ( $plotcfg{interval} eq 'mission'){
				%all_interval = %mission_interval;
			    }
			}
			if (defined $plotcfg{black}->{interval}){
			    if ($plotcfg{black}->{interval} eq 'mission'){
				%all_interval = %mission_interval;
			    }
			}
			
			
			$bin_type = (defined $plotcfg{red_all}->{bin_over}) ? $plotcfg{red_all}->{bin_over} : $top_level_bin_type;
			
			%where = (defined $plotcfg{red_all}->{where} ) ? %{$plotcfg{red_all}->{where}} : ();
			

			if ("$time_start_field" eq "$time_stop_field"){
			    %time_where = ( "$time_start_field" => { '>=' => $interval{tstart} ,
								     '<=' => $interval{tstop} } );
			}
			else{
			    %time_where = (  "$time_start_field" => { '>=' => $interval{tstart} },
					     "$time_stop_field"  => { '<=' => $interval{tstop} },
					     );
			}

			my $red_all_select = Ska::SQL::Select->new({ table => $table,
								       fields => $plotcfg{red_all}->{fields},
								       where => { $bin_type => { '>=' => $bin, '<' => $bin + $bin_size },
										  %where,
										  %time_where,
									      },						
								   });
		    
#		    print $black_select->get_select_string(), "\n";
			my $red_allref = $red_all_select->run({ handle => $handle, type => 'array' });

			my $red_cnt = $red_ref->[0]->{red};
			my $red_all_cnt = $red_allref->[0]->{red_all};

			my $ratio = ( $red_all_cnt > 0 ) ? $red_cnt/$red_all_cnt : 0;
			my $err_low_lim = ($red_all_cnt > 0) ? ((sqrt($red_cnt)/$red_all_cnt) * 1) : 0;
			push @red_m, -($err_low_lim);
        # set the upper limit on the error bar to 100% (by setting the size of the bar to 100-value if
        # the bar is going to end up over 1)
			my $err_high_lim = ($err_low_lim + $ratio) < 1 ? $err_low_lim : 1 - $ratio;
			push @red_p, $err_high_lim;
			push @red, $ratio;
		    }
		    else{
			push @red, $red_ref->[0]->{red} * $red_scale ;
			push @red_m, 0;
			push @red_p, 0;
		    }
		}

#			print "$bin red ", $red_ref->[0]->{red}, "\n";
	    }
		
	    
	   

#	    print Dumper @data_bin;
#	    print Dumper @black;
#	    print Dumper @red_x100;


	    # find min non-zero value
	    if (scalar(@black)){
		my $black_pdl = pdl(@black);
#		print $black_pdl, "\n";
		my $min_non_zero = $black_pdl->( which( $black_pdl > 0) )->min();
		my $y_black =  $plot_padlog ? $black_pdl + ($min_non_zero/10.) : $black_pdl;
		
		push @plot_array,   
		'x' => pdl(@data_bin),
		'y' => $y_black;
		
		if (scalar(@black_m) and scalar(@black_p)){
		   push @plot_array, 
		   'y_m' => pdl(@black_m),
		   'y_p' => pdl(@black_p),
		   ;
	       }
		push @plot_array,
		options => {center => 1},
		charsize => {symbol => 1.2,
			     title => 2.0,
			     axis => 2.0,
			 },
		plot => 'points',
		;
		
		if (scalar(@red)){
		    my $red_pdl = pdl(@red);
		    my $y_red = $plot_padlog ? $red_pdl + ($min_non_zero/10.) : $red_pdl;
		    
		    
		    push @plot_array,
		    'x' => pdl(@data_bin)+0.01,
		    'y' => $y_red,
		    ;
		    if (scalar(@red_m) and scalar(@red_p)){
			push @plot_array, 
			'y_m' => pdl(@red_m),
			'y_p' => pdl(@red_p),
			;
		    }
		    push @plot_array,
		    options => {center => 1},
		    charsize => {symbol => 1.2,
				 title => 2.0,
				 axis => 2.0,
			     },
		    color => { symbol => 'red', err => 'red' },
		    plot => 'points',
		    ;
		    
		}
	    }

	    

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


=pod 

=head1 AUTHOR

Jean Connelly, E<lt>jeanconn@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Smithsonian Astrophysical Observatory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.


=cut




