<?php

$web_base = "/mta/ASPECT/guide_stat_reports";
$gs_base = '/proj/sot/ska/www/ASPECT/guide_stat_reports';
$host  = $_SERVER['HTTP_HOST'];
$uri  = rtrim($_SERVER['PHP_SELF'], "/\\");
$script = $_SERVER['SCRIPT_NAME'];

// $n_months = 12;
// $n_quarters = 4;
// $n_semi = 2;



// print "$uri vs $web_base vs $script";

?>


<HTML>
<HEAD>
<TITLE>Guide Statistics Report</TITLE>
<link href="/mta/ASPECT/aspect.css" rel="stylesheet" type="text/css" media="all" />
  <style type="text/css">
  body { min-width:900px; background:url('http://asc.harvard.edu/mta/ASPECT/blue_paper.gif'); }
}
</style>

</HEAD>
<BODY>

<A HREF="<?php print "http://${host}/${web_base}" ?>">Home</A>

<?php

$id_info = ltrim( $script, "$web_base");
$id_info = rtrim( $id_info, "index.php");
$id_parts = explode("/", $id_info);

$year = $id_parts[0];
$id = $id_parts[1];

$type = "";
$next = "";
$prev = "";


if (preg_match( '/M\d{2}/', $id )){
  $type = 'month';
  $id = ltrim( $id, "M" );
  $next_id = $id + 1;
  $next_year = $year;
  $prev_id = $id - 1;
  $prev_year = $year;
  if ($next_id > 13){
    $next_id = 1;
    $next_year = $next_year + 1;
  }
  if ($prev_id == 0 ){
    $prev_id = 12;
    $prev_year = $prev_year - 1;
  }
  $next = sprintf( "%04d/M%02d", $next_year, $next_id );
  $prev = sprintf( "%04d/M%02d", $prev_year, $prev_id );
 }
if (preg_match( '/S\d{1}/', $id )){
  $type = 'semi';
  $id = ltrim( $id, "S" );
  $next_id = $id + 1;
  $next_year = $year;
  $prev_id = $id - 1;
  $prev_year = $year;
  if ($next_id == 3){
    $next_id = 1;
    $next_year = $next_year + 1;
  }
  if ($prev_id == 0 ){
    $prev_id = 2;
    $prev_year = $prev_year - 1;
  }
  $next = sprintf( "%04d/S%d", $next_year, $next_id );
  $prev = sprintf( "%04d/S%d", $prev_year, $prev_id );

 }
if (preg_match( '/Q\d{1}/', $id )){
  $type = 'quarter';
  $id = ltrim( $id, "Q");
  $next_id = $id + 1;
  $next_year = $year;
  $prev_id = $id - 1;
  $prev_year = $year;
  if ($next_id == 5){
    $next_id = 1;
    $next_year = $next_year + 1;
  }
  if ($prev_id == 0 ){
    $prev_id = 4;
    $prev_year = $prev_year - 1;
  }
  $next = sprintf( "%04d/Q%d", $next_year, $next_id );
  $prev = sprintf( "%04d/Q%d", $prev_year, $prev_id );

 }
if (preg_match( '/YEAR/', $id )){
  $type = 'year';
  $next_year = $year + 1;
  $prev_year = $year - 1;

  $next = sprintf( "%04d/YEAR", $next_year);
  $prev = sprintf( "%04d/YEAR", $prev_year);

  
 }


printf(" <A HREF=\"http://${host}/${web_base}/${prev}/index.php\">Prev</A>");
printf(" <A HREF=\"http://${host}/${web_base}/${next}/index.php\">Next</A>");
printf(" <A HREF=\"http://${host}/${web_base}/${type}_summary\">Summary</A>");



//  $nextid = $id + 1;
//  $nextyear = $year;
//  $previd = $id - 1;
//  $prevyear = $year;
//  if ($nextid == 13){
//    $nextid = 1;
//    $nextyear = $nextyear + 1;
//  }
//  if ($previd == 0){
//    $previd = 12;
//    $prevyear = $prevyear - 1;
//  }
//  //  print "$host $uri";
//  $next = sprintf("http://${host}${uri}?year=%04d&id=%02d&_submit_check=1&submit=Submit", $nextyear, $nextid);
//  $prev = sprintf("http://${host}${uri}?year=%04d&id=%02d&_submit_check=1&submit=Submit", $prevyear, $previd);
//  print "<A HREF=\"$prev\">PREV</A>  <A HREF=\"$next\">NEXT</A>";
// }


//
//function show_overview(){
//}
//  
//
//function show_form( $year, $id ){
//  print '<FORM ACTION="folder.php" METHOD="get">';
//  print "Year <input type=\"text\" name=\"year\" value=\"$year\">";
//  print "ID <input type=\"text\" name=\"id\" value=\"$id\">";
//  print ' <input type="hidden" name="_submit_check" value="1"/>';
//  print ' <input type="submit" name="submit" value="Submit">';
//  print '<input type="reset" name="reset" value="Clear It">';
//  print '</FORM>';
//}
//
//function show_nav( $year, $id){
//  if (preg_match( '/^\d{2}$/', $id)){
//    $nextid = $id + 1;
//    $nextyear = $year;
//    $previd = $id - 1;
//    $prevyear = $year;
//    if ($nextid == 13){
//      $nextid = 1;
//      $nextyear = $nextyear + 1;
//    }
//    if ($previd == 0){
//      $previd = 12;
//      $prevyear = $prevyear - 1;
//    }
//    //  print "$host $uri";
//    $next = sprintf("http://${host}${uri}?year=%04d&id=%02d&_submit_check=1&submit=Submit", $nextyear, $nextid);
//    $prev = sprintf("http://${host}${uri}?year=%04d&id=%02d&_submit_check=1&submit=Submit", $prevyear, $previd);
//    print "<A HREF=\"$prev\">PREV</A>  <A HREF=\"$next\">NEXT</A>";
//  }
//}
//
//show_nav( '2001', '01' )

//  
//
//
//}
//
//function process_form(){
//  //  show_form();
//  //  print $_POST[datestring];
//  show_form( $_GET[year], $_GET[id] );
//  show_nav( $_GET[year], $_GET[id] );
//  show_page( $_GET[year], $_GET[id] );
//  
//}
//
//function validate_form(){
//}
//
//
//if (array_key_exists('_submit_check',$_GET)) {
//  // If validate_form() returns errors, pass them to show_form()
//  if ($form_errors = validate_form()) {
//    show_form($form_errors);
//  } else {
//    // The submitted data is valid, so process it
//    process_form();
//  }
// } else {
//  // The form wasn't submitted, so display
//  show_form();
//  show_overview();
// }
//}

?>


<H2>Guide Statistics Report<?php print file_get_contents("title.htm") ?></H2>
<H3><?php print file_get_contents("human_date_start.htm") ?> through
<?php print file_get_contents("human_date_stop.htm") ?> </H3>


<TABLE BORDER=1>
<TR><TD>TSTART</TD><TD><?php print file_get_contents("date_start.htm")?></TD></TD>
    <TD>TSTOP</TD><TD><?php print file_get_contents("date_stop.htm")?></TD></TR>
</TABLE>
<BR />

<?php print file_get_contents("main_table.htm")?>


<TABLE>
<TD><?php print file_get_contents("histogram.htm")?></TD><TD><?php print file_get_contents("scatterplot.htm")?></TD>
</TABLE>

<?php print file_get_contents("mag_table.htm")?>

</BODY>
</HTML>



