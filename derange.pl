#!/usr/bin/perl -w

######################################################################
# 
#                    DeRange Media Tool
my $version =        "0.20180223a";
#
# Description:       DeRange is a GUI utility which tracks video 
#                    media files, Normalizes and Compresses audio, 
#                    manages tags, and creates tag-based XSPF 
#                    playlists plus more.
# Author:            Michael H Fahey
# Author URI:        https://artisansitedesigns.com/asdpersons/michael-h-fahey/
# License:           GPL3
# Date:              02-23-2018
# 
######################################################################

use Config::Simple;
use File::Basename;
use IO::File;
use Tk;
use Tk::Canvas;
use Tk::Checkbox;
use Tk::DialogBox;
use Tk::LabEntry;
use Tk::MListbox;
use Tk::Menu;
use Tk::NoteBook;
use Tk::ProgressBar;
use Tk::Spinbox;
use Tk::TableMatrix;
use XML::Simple;
use XML::Writer;
use strict;

my $debug=0;

# ----------------------------------------------------------------------------------------------------
#                     external binaries
# ----------------------------------------------------------------------------------------------------
my $CKSUM="/usr/bin/cksum";
my $ECHO="/bin/echo";
my $FIND="/usr/bin/find";
my $FFMPEG="/usr/bin/ffmpeg";
my $FFPROBE="/usr/bin/ffprobe";
my $GREP="/bin/grep";
my $LS="/bin/ls";
my $MKDIR="/bin/mkdir";
my $MV="/bin/mv";
my $NICE="/usr/bin/nice -10";
my $RM="/bin/rm";
my $SORT="/usr/bin/sort";
my $TOUCH="/usr/bin/touch";


# ----------------------------------------------------------------------------------------------------
#                      colors 
# ----------------------------------------------------------------------------------------------------
my $orange="#E74D09";
my $blue  = "#0044FF";
my $blue2 = "#002DB2";
my $offwhite="#E2DEE5";
my $lightgray="#7D7B7F";
my $verylightgray="#D4D5DE";
my $darkgray="#3F3E40";

my $appback=$blue2;
my $btnback='white';
my $btnfore=$blue;


# ----------------------------------------------------------------------------------------------------
#                      table column definitions
# ----------------------------------------------------------------------------------------------------
my $COL=0;
my $COL_MEDIAFILE=$COL++;
my $COL_TAGS=$COL++;
my $COL_RATING=$COL++;
my $COL_WEIGHT=$COL++;
my $COL_MAXVOL=$COL++;
my $COL_MEANVOL=$COL++;
my $COL_COMPRESSED=$COL++;
my $COL_NORMALIZED=$COL++;
my $COL_FILESIZE=$COL++;
my $COL_TIMESTAMP=$COL++;
my $COL_VCODEC=$COL++;
my $COL_VBITRATE=$COL++;
my $COL_ACODEC=$COL++;
my $COL_ABITRATE=$COL++;
my $COL_CONTAINER=$COL++;

# ----------------------------------------------------------------------------------------------------
#                     button dimensions
# ----------------------------------------------------------------------------------------------------
my $btnwidth=12;
my $btnheight=1;


# ----------------------------------------------------------------------------------------------------
#                    directories and files 
# ----------------------------------------------------------------------------------------------------
my $homedir = $ENV{"HOME"};
my $configdir = $homedir . "/.derange";
my $configfile = $configdir . "/config";
my $playlistconfigfile = $configdir . "/config.playlist";
my $cachedir = $configdir . "/cache";
my $logfilename = $configdir . "/logfile";
my $tempdir = $configdir . "/tmp";
my $tempfile= $tempdir . "/ffmpeg.tmp";
my $originaldir = "/originals";


# ----------------------------------------------------------------------------------------------------
#                     globals
# ----------------------------------------------------------------------------------------------------
my $newrating=0;
my $newweight=0;
my $truncatelength="00:22:30.000";
my $crop_width="320";
my $crop_height="240";
my $crop_x="50";
my $crop_y="0";
my $newtags="";
my $deltags="";
my $xml_version = 0.09;
my $running;
my $alwaysDeleteOrphanCache=0;
my $alwaysUpdateMediaData=0;
my $ffmpegCompressFilter= '-af "aformat=channel_layouts=stereo, compand=0 0:1 1:-90/-900 -70/-70 -21/-21 0/-15:0.01:12:0:0"';
my $arraymax=1000000;  # this sets an arbitrary max value for the outputlist index


# ----------------------------------------------------------------------------------------------------
#                     logfile
# ----------------------------------------------------------------------------------------------------
open my $logfile,  ">", $logfilename;



# ----------------------------------------------------------------------------------------------------
#                    sub prototypes 
# ----------------------------------------------------------------------------------------------------
sub loadLibrary();
sub loadImportDirectory();


# ----------------------------------------------------------------------------------------------------
#                    verify that certain directories and files exist
# ----------------------------------------------------------------------------------------------------
&verifyDir ($configdir);
&verifyDir ($cachedir);
&verifyDir ($tempdir);


# ----------------------------------------------------------------------------------------------------
#                    settings and configuration file 
# ----------------------------------------------------------------------------------------------------
my $cfg = new Config::Simple($configfile);

my $screenGeometry = $cfg->param("derange.Geometry");
my $workingdirectory = $cfg->param("derange.WorkingDirectory");
my $renamefiles = $cfg->param("derange.RenameFiles");
my $fixcache = $cfg->param("derange.FixCache");
my $localroot = $cfg->param("derange.PlayListLocalRoot");

my $playlistname;
my $playlistcount;
my $includeTags;
my $excludeTags;
my $playlistroot;
my $playlistoutputpath;


# ----------------------------------------------------------------------------------------------------
#                     TK main window 
# ----------------------------------------------------------------------------------------------------
my $mw = MainWindow->new();
$mw->geometry($screenGeometry);
$mw->title("DeRange Media Tool v" . $version );
# catch the x button to close the window
$mw->protocol(WM_DELETE_WINDOW=> \&saveAndExit);
$mw->configure (-background=>'green');

#my $mwIcon = $mw->Photo(-file => dirname(__FILE__) . "/db-gauge256.gif", -format => 'gif');
#$mw->Icon(-image => $mwIcon); 

# ----------------------------------------------------------------------------------------------------
#                     fonts 
# ----------------------------------------------------------------------------------------------------
my $smallFont = $mw->fontCreate( -size => 8 );
my $medFont = $mw->fontCreate( -size => 9 );
my $bigfont = $mw->fontCreate( -size => 12 );
my $noFont = $mw->fontCreate( -size => 2 );


# ----------------------------------------------------------------------------------------------------
#                     menu widgets
# ----------------------------------------------------------------------------------------------------
$mw->configure(-menu => my $menu = $mw->Menu);
my $filemenu = $menu -> cascade ( -label => 'File'); 
my $editmenu = $menu -> cascade ( -label => 'Edit'); 
$filemenu -> command ( -label => "Exit",
                        -command=> \&saveAndExit );
$editmenu -> command ( -label => "Compress",
                        -command=>sub { processSelectedMedia("compress"); } );
$editmenu -> command ( -label => "Normalize",
                        -command=>sub { processSelectedMedia("normalize"); } );
$editmenu -> command ( -label => "Comp+Norm",
                        -command=>sub { processSelectedMedia("compressnormalize"); } );
$editmenu -> command ( -label => "Set Compress data",
                        -command=>sub { 
                                     my $newcompress;
                                     my $d = $mw->DialogBox(-title => "Compress Time",  
                                                            -buttons => ["Apply", "Cancel"]);
                                     my $msgtext = $d->add("LabEntry",
                                                           -label=> 'new compress timestamp',
                                                           -labelPack => [ -side => "left" ],
                                                           -textvariable => \$newcompress)->pack();
                                     my $response = $d->Show;
                                     if ($response eq "Apply") {
                                        processSelectedLibraryData("setCData",$newcompress); 
                                     }
                                  } );
$editmenu -> command ( -label => "Set Normalize data",
                        -command=>sub { 
                                     my $newnormalize;
                                     my $d = $mw->DialogBox(-title => "Normalize Time",  
                                                            -buttons => ["Apply", "Cancel"]);
                                     my $msgtext = $d->add("LabEntry",
                                                           -label=> 'new normalize timestamp',
                                                           -labelPack => [ -side => "left" ],
                                                           -textvariable => \$newnormalize)->pack();
                                     my $response = $d->Show;
                                     if ($response eq "Apply") {
                                        processSelectedLibraryData("setNData",$newnormalize); 
                                     }
                                } );
$editmenu -> command ( -label => "Set Tag data",
                        -command=>sub {
                                     my $settags;
                                     my $d = $mw->DialogBox(-title => "Add Tag",  
                                                            -buttons => ["Apply", "Cancel"]);
                                     my $msgtext = $d->add("LabEntry",
                                                           -label=> 'new tags',
                                                           -labelPack => [ -side => "left" ],
                                                           -textvariable => \$settags)->pack();
                                     my $response = $d->Show;
                                     if ($response eq "Apply") {
                                        processSelectedLibraryData("setTData",$settags); 
                                     }
                                } );





# ----------------------------------------------------------------------------------------------------
#        buttons above tabs
# ----------------------------------------------------------------------------------------------------

my $frameButtons= $mw->Frame()->pack(-side=>'top',
                                      -expand => 0,
                                     -fill => 'x');
my $canvButtons = $frameButtons->Canvas (-background=>$appback,
                                         -highlightthickness=>0,
                                         -borderwidth=>0 )
                                         ->pack(-side=>'top',-expand=>0, -fill=>'x');;

my $btnStop = $canvButtons->Button(-text=>"Stop",-width=>$btnwidth,-height=>$btnheight,
               -anchor  =>"center",
               -background=> $lightgray,
               -foreground=> $darkgray,
               -borderwidth=>0,
               -command=> 
                 sub {
                    $running=0;
                }  );
my $btnExit= $canvButtons->Button(
                -text=>"Exit",
                -background=> 'white',
                -foreground=> $btnfore,
                -borderwidth=>0,
                -width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
				-command=> \&saveAndExit 
                );
$btnExit->pack(-side => 'right');
$btnStop->pack(-side => 'right');



# ----------------------------------------------------------------------------------------------------
#                     notebook widget
# ----------------------------------------------------------------------------------------------------
my $notebook = $mw->NoteBook(-backpagecolor=>$appback,
                             -background=>'white',
                             -focuscolor=>$orange )->pack(-side=>'top',-expand=>1, -fill => 'both');





# ----------------------------------------------------------------------------------------------------
#                    library tab widgets
# ----------------------------------------------------------------------------------------------------

my $notepageLibrary = $notebook->add("library", 
                                      -label=>"Media Library");
my $frameLibraryButtons= $notepageLibrary->Frame()->pack(-side=>'top',-expand => 0,-fill => 'x');
my $canvLibraryButtons = $frameLibraryButtons->Canvas ( -background=>'white' )->pack(-side=>'top',-expand=>0, -fill=>'both');

# frame for library table and table itself
my $frameLibraryListbox= $notepageLibrary->Frame()->pack(-side=>'left',-expand => 1,-fill => 'both');

my $lbxLibrary = $frameLibraryListbox-> Scrolled ( "MListbox", -foreground=>"black", -background=>"white", -scrollbars=>"e")->pack(-side=>'left',-expand => 1,-fill => 'both');


my $canvLibraryButtons1  = $canvLibraryButtons-> Canvas (-background=>'white') ->pack (-side=>'left',-expand=>0,-fill=>'y');
my $canvLibraryButtons2  = $canvLibraryButtons-> Canvas (-background=>'white')->pack (-side=>'right',-fill=>'x');
my $canvLibraryButtons3  = $canvLibraryButtons-> Canvas (-background=>'white')->pack (-side=>'right',-fill=>'x');

my $canvLibraryButtons4  = $canvLibraryButtons2-> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');
my $canvLibraryButtons5  = $canvLibraryButtons2-> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');
my $canvLibraryButtons6  = $canvLibraryButtons3-> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');
my $canvLibraryButtons7  = $canvLibraryButtons3-> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');

my $canvLibraryButtons8 = $canvLibraryButtons1 -> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');
my $canvLibraryButtons9 = $canvLibraryButtons1 -> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');
my $canvLibraryButtons10 = $canvLibraryButtons1 -> Canvas (-background=>'white')->pack (-side=>'top',-fill=>'x');


my $btnCompressAudio = $canvLibraryButtons8->Button(-text=>"Compress",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                -disabledforeground=>$lightgray,
				-command => sub { processSelectedMedia("compress"); } )->pack(-side=>'left');

my $btnNormalizeAudio = $canvLibraryButtons8->Button(-text=>"Normalize",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
				-command => sub { processSelectedMedia("normalize"); } )->pack(-side=>'left');

my $btnCompAndNormAudio = $canvLibraryButtons9->Button(-text=>"Compress + Normalize",-width=>$btnwidth*2.4,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
				-command => sub { processSelectedMedia("compressnormalize"); } )->pack(-side=>'left');


my $btnTruncate = $canvLibraryButtons9->Button(-text=>"Truncate",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                        -command=>sub { processSelectedMedia("truncate" ); }
				 )->pack(-side=>'left');
my $entTruncate = $canvLibraryButtons9-> Entry (
                                    -textvariable=> \$truncatelength,
                                    -background=>'white',
                                    -width=>15,
                                     )-> pack (-side=>'right');

my $btnCrop = $canvLibraryButtons10->Button(-text=>"Crop",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                        -command=>sub { processSelectedMedia("crop" ); }

				 )->pack(-side=>'left');
my $entCropWidth = $canvLibraryButtons10-> Entry (
                                    -textvariable=> \$crop_width,
                                    -background=>'white',
                                    -width=>15,
                                     )-> pack (-side=>'left');
my $entCropHeight = $canvLibraryButtons10-> Entry (
                                    -textvariable=> \$crop_height,
                                    -background=>'white',
                                    -width=>15,
                                     )-> pack (-side=>'left');
my $entCropX = $canvLibraryButtons10-> Entry (
                                    -textvariable=> \$crop_x,
                                    -background=>'white',
                                    -width=>15,
                                     )-> pack (-side=>'left');
my $entCropY = $canvLibraryButtons10-> Entry (
                                    -textvariable=> \$crop_y,
                                    -background=>'white',
                                    -width=>15,
                                     )-> pack (-side=>'left');





my $btnSetRating = $canvLibraryButtons4->Button(-text=>"Set Rating",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                        -command=>sub { processSelectedLibraryData("setRData",$newrating); }
				 )->pack(-side=>'left');
my $entNewRating = $canvLibraryButtons4-> Entry (
                                    -textvariable=> \$newrating,
                                    -background=>'white',
                                    -width=>5,
                                     )-> pack (-side=>'right');

my $btnSetWeight = $canvLibraryButtons5->Button(-text=>"Set Weight",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                        -command=>sub { processSelectedLibraryData("setWData",$newweight); }
				 )->pack(-side=>'left');
my $entNewWeight = $canvLibraryButtons5-> Entry (
                                    -textvariable=> \$newweight,
                                    -background=>'white',
                                    -width=>5,
                                     )-> pack (-side=>'right');

my $btnAddTags = $canvLibraryButtons6->Button(-text=>"Add Tags",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                -font=>$medFont,
                        -command=>sub { 
                                        processSelectedLibraryData("addTData",$newtags); 
                                     }
				 )->pack(-side=>'left');
my $entNewTags = $canvLibraryButtons6-> Entry (
                                    -textvariable=> \$newtags,
                                    -background=>'white',
                                    -width=>25,
                                     )-> pack (-side=>'right');


my $btnDelTags = $canvLibraryButtons7->Button(-text=>"Remove Tags",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
                        -command=>sub { 
                                        processSelectedLibraryData("delTData",$deltags); 
                                     }
				 )->pack(-side=>'left');
my $entDelTags = $canvLibraryButtons7-> Entry (
                                    -textvariable=> \$deltags,
                                    -background=>'white',
                                    -width=>25,
                                     )-> pack (-side=>'right');



$lbxLibrary->columnInsert( 'end' , -text=>'Media File', -sortable=>1, -width=>100, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'tags', -sortable=>1, -width=>20, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'rating', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'weight', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'maxvol', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'meanvol', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'compressed', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'normalized', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'filesize', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'timestamp', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'Vcodec', -sortable=>1, -width=>0,  -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'Vbitrate', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'Acodec', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'Abitrate', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'container', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);
$lbxLibrary->columnInsert( 'end' , -text=>'sortable', -sortable=>1, -width=>0, -separatorcolor => $verylightgray);

$lbxLibrary->configure( -background=> "#FFF2ED");
$lbxLibrary->configure( -selectmode=>'extended');
$lbxLibrary->configure( -font => $smallFont);
$lbxLibrary->sort(0, 0);



# ----------------------------------------------------------------------------------------------------
#                       managed folders tab widgets
# ----------------------------------------------------------------------------------------------------
my $notepageFolders = $notebook->add("folders" , -label=>"Managed Folders");


# ----------------------------------------------------------------------------------------------------
#                      import tab widgets 
# ----------------------------------------------------------------------------------------------------

my $notepageImport = $notebook->add("import", -label => "Import" );

my $canvImportButtons= $notepageImport->Canvas(-background=>'white')->pack(-side=>'top',-expand => 0,-fill => 'x');

my $btnDir = $canvImportButtons->Button(-text=>"Directory",-width=>$btnwidth,-height=>$btnheight,
               -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
               -command => 
                  sub {
                     $workingdirectory = $canvImportButtons->chooseDirectory(
					     -initialdir=>$workingdirectory);
                     loadImportDirectory();
                  } ) ->pack(-side => 'left');
my $entryDir= $canvImportButtons->Entry (-textvariable => \$workingdirectory,-width=>40) ->pack(-side => 'left');
$entryDir -> configure ( -font=>$bigfont );

my $btnReload = $canvImportButtons->Button(-text=>"Reload",-width=>$btnwidth,-height=>$btnheight,
                -anchor  =>"center",
                -background=> 'white',
                -foreground=> $btnfore,
                -pady=>0,
                -font=>$medFont,
				-command => \&loadImportDirectory ) ->pack(-side => 'left');

my $canvImportButtons2= $notepageImport->Canvas(-background=>'white')->pack(-side=>'top',-expand => 0,-fill => 'x');

my $btnImportSelectNew = $canvImportButtons2-> Button (
                                                  -width=>$btnwidth,-height=>$btnheight,
                                                  -text=>"Select New",
                                                  -background=> 'white',
                                                  -foreground=> $btnfore,
                                                  -pady=>0,
                                                  -font=>$medFont,
                                                  -command => \&importSelectNew )
                                                  ->pack(-side=>"left");

my $btnImportSelected = $canvImportButtons2-> Button (
                                                  -width=>$btnwidth,-height=>$btnheight,
                                                  -text=>"Import",
                                                  -pady=>0,
                                                  -background=> 'white',
                                                  -foreground=> $btnfore,
                                                  -font=>$medFont,
                                                  -command => \&importSelected )
                                                  ->pack(-side=>"left");

my $frameImportSkipbox= $notepageImport->Frame()->pack(-side=>'bottom', -expand => 1,-fill => 'x');
my $frameImportedListbox= $notepageImport->Frame()->pack(-side=>'bottom',-expand => 1,-fill => 'both');
my $frameImportListbox= $notepageImport->Frame()->pack(-side=>'top',-expand => 1,-fill => 'both');

my $lbxImport = $frameImportListbox-> Scrolled ( "MListbox", -scrollbars=>"e")->pack(-side=>'left',-expand => 1,-fill => 'both');

my $lbxImported = $frameImportedListbox-> Scrolled ( "MListbox", -scrollbars=>"e")->pack(-side=>'left',-expand => 1,-fill => 'both');

my $lbxImportSkip = $frameImportSkipbox-> Scrolled ( "MListbox", -height=>5, -scrollbars=>"e")->pack(-side=>'left',-expand => 1,-fill => 'both');

$lbxImport ->columnInsert( 'end' , -text=>'Importable Files', -sortable=>1, -width=>200);
$lbxImport->configure( -font => $smallFont);
$lbxImport->configure( -selectmode=>'extended');
$lbxImport->configure( -background=> '#F5F5F5');
$lbxImport->sort(0, 1);

$lbxImported->columnInsert( 'end' , -text=>'Media Already In Library', -sortable=>1, -width=>200);
$lbxImported->configure( -background=> "#FFF2ED");
$lbxImported->configure( -font => $smallFont);
$lbxImported->sort(0, 1);

$lbxImportSkip ->columnInsert( 'end' , -text=>'Non-importable files', -sortable=>1, -width=>200);
$lbxImportSkip->configure( -background=> $verylightgray);
$lbxImportSkip->configure( -foreground=> 'red');
$lbxImportSkip->configure( -font => $smallFont);
$lbxImportSkip->sort(0, 1);

$lbxImport->pack(-side=>'top',-expand => 1,-fill => 'both');





# ----------------------------------------------------------------------------------------------------
#            playlist tab widgets
# ----------------------------------------------------------------------------------------------------


my $notepagePlaylists = $notebook->add("playlists", -label => "Playlists" );

my $framePlaylistControls = $notepagePlaylists -> Frame()->pack(-side=>'top', -anchor => 'nw', -expand => 1, -fill=>'x');

my $btnMakePlaylists = $framePlaylistControls->Button(-text=>"Make Playlists",-width=>$btnwidth*2,-height=>$btnheight,
                -anchor  =>"center",
                -background=> $blue,
                -foreground=> $offwhite,
                -disabledforeground=>$lightgray,
				-command => sub { makePlaylists2(); } )->pack(-side=>'right');

my $framePlaylistControls1 = $framePlaylistControls -> Frame()->pack(-side=>'top', -anchor => 'nw',  -expand => 1, -fill=>'x');

my $playlistArray = {};

# playlist configuration loads from xml

my $xmlplaylistfile = new XML::Simple;
my $xmlplaylistdata = $xmlplaylistfile->XMLin( $playlistconfigfile, forcearray=>1, SuppressEmpty => '');
$playlistArray->{"0,0"} =  "Playlist Name";
$playlistArray->{"0,1"} =  "Number of Lists";
$playlistArray->{"0,2"} =  "Include Tags";
$playlistArray->{"0,3"} =  "Exclude Tags";

my $listcount = 1;
for my $playlistitem (@ { $xmlplaylistdata->{playlist} }) {
   $playlistArray->{"$listcount,0"} = $playlistitem->{name} ;
   $playlistArray->{"$listcount,1"} = $playlistitem->{count} ;
   $playlistArray->{"$listcount,2"} = $playlistitem->{include} ;
   $playlistArray->{"$listcount,3"} = $playlistitem->{exclude} ;
   $listcount++;
}

my $tmxPlaylists = $framePlaylistControls1-> Scrolled ( "TableMatrix", 
                                                        -cols=>4 , 
                                                        -rows =>$listcount,
                                                        -colstretchmode => 'all',
                                                        -variable => $playlistArray )
                                                        ->pack( 
                                                                 -anchor => 'nw',
                                                                 -side=>'top',
                                                                 -expand=>1, 
                                                                 -fill => 'both');

my $btnAddPlaylist = $framePlaylistControls1->Button(-text=>"Add Playlist",-width=>$btnwidth*2,-height=>$btnheight,
                -anchor  =>"center",
                -background=> $blue,
                -foreground=> $offwhite,
                -disabledforeground=>$lightgray,
				-command => sub { $tmxPlaylists->insertRows('end') } )->pack(-side=>'left');


my $framePlaylistControls2 = $framePlaylistControls -> Frame()->pack(-side=>'top', -anchor => 'nw',  -expand => 1, -fill=>'x');

my $playlistRootsArray = {};

$playlistRootsArray->{"0,0"} =  "Playlist Root";
$playlistRootsArray->{"0,1"} =  "Output Path";

my $rootcount = 1;
for my $playlistitem (@ { $xmlplaylistdata->{listroot} }) {
   $playlistRootsArray->{"$rootcount,0"} = $playlistitem->{root} ;
   $playlistRootsArray->{"$rootcount,1"} = $playlistitem->{output_path} ;
   $rootcount++;
}

my $tmxPlaylistRoots = $framePlaylistControls2-> Scrolled ( "TableMatrix", 
                                                        -cols=>2 , 
                                                        -rows =>$rootcount,
                                                        -colwidth => 35,
                                                        -variable => $playlistRootsArray )
                                                        ->pack( 
                                                                 -anchor => 'nw',
                                                                 -side=>'left',
                                                                 -fill => 'x');

my $btnAddPlaylistRoot = $framePlaylistControls2->Button(-text=>"Add Playlist Root",-width=>$btnwidth*2,-height=>$btnheight,
                -anchor  =>"center",
                -background=> $blue,
                -foreground=> $offwhite,
                -disabledforeground=>$lightgray,
				-command => sub { $tmxPlaylistRoots->insertRows('end'); $rootcount++; $tmxPlaylistRoots->configure("-height",$rootcount); $mw->update(); } )->pack(-side=>'left');



# ----------------------------------------------------------------------------------------------------
#                      settings tab widgets
# ----------------------------------------------------------------------------------------------------

my $notepageSettings = $notebook->add("settings", -label => "Settings" );

my $lblAFilter = $notepageSettings-> Label ( 
                                     -text=>"Compress Audio Filter",
                                     )->pack (-side=>'left');
my $entAFilter = $notepageSettings-> Entry (
                                    -textvariable=> $ffmpegCompressFilter,
                                    -width=>100,
                                     )-> pack (-side=>'left');
my $lblARename = $notepageSettings-> Label ( 
                                     -text=>"Rename Media Files",
                                     )->pack (-side=>'left');
my $cbxRenameFiles = $notepageSettings-> Checkbox ( -variable => \$renamefiles,
                                                      -onvalue  => 'On',
                                                      -offvalue => 'Off')->pack(-side=>'left');
my $lblFixCache = $notepageSettings-> Label ( 
                                     -text=>"Update/Fix Cache",
                                     )->pack (-side=>'left');
my $cbxFixCache = $notepageSettings-> Checkbox ( -variable => \$fixcache,
                                                      -onvalue  => 'On',
                                                      -offvalue => 'Off')->pack(-side=>'left');




# ----------------------------------------------------------------------------------------------------
#             status bar and progress bar widgets
# ----------------------------------------------------------------------------------------------------

my $statustext="Ready";
my $statusframe= $mw->Frame()->pack(-side=>'top',-expand => 0,-fill => 'x');

my $percentdone=0;
my $progressbar = $statusframe->ProgressBar(
                -width => 50,
                -from => 0,
                -to => 100,
                -blocks => 100,
                -foreground=>$orange,
                -variable => \$percentdone
                )->pack(-fill => 'x');
my $lblStatus = $statusframe-> Label(-textvariable=>\$statustext,-width=>80,-height=>1);
$lblStatus->pack(-side => 'left',-anchor=>'w');



# ----------------------------------------------------------------------------------------------------
#                main loop stuff 
# ----------------------------------------------------------------------------------------------------

if ($debug == 0) {
   loadLibrary();
   $lbxLibrary->yview (moveto=> 1);
   loadImportDirectory();
}

MainLoop();





# ----------------------------------------------------------------------------------------------------
#                 subroutines
# ----------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------
sub importSelectNew(){
# ----------------------------------------------------------------------------------------------------
   $lbxImport->selectionClear(0, 'end');

   my $thisRow = 0;
   my $numRows = $lbxImport->index('end');
   while ( $thisRow < $numRows) {
      my @rowContents = $lbxImport->getRow ($thisRow);
           $lbxImport->selectionSet ($thisRow);
      $thisRow++;
   }
}

# ----------------------------------------------------------------------------------------------------
sub importSelected(){  
# ----------------------------------------------------------------------------------------------------
   my @selRows = $lbxImport->curselection();
   my $numberofrows = @selRows ;

   $running=1;
   $btnStop->configure( -background=>'red', -foreground=>$offwhite);

   $percentdone=0;
   $mw->Busy();
   $mw->update();

   foreach (@selRows ) {

      if ($running==1){

        my @selImportRow = $lbxImport->getRow($_);
        my $selMediaFile = $selImportRow[0];
        my ($bareMediaFile, $barepath) = fileparse ($selMediaFile);

        my $cachefilename = $cachedir . "/" . $bareMediaFile . ".data";
        $cachefilename =~ s/ /_/gsm;

        # $statustext = "importing into library " .  $bareMediaFile;
        $lblStatus->pack(-side => 'left',-anchor=>'w');

        makeAndWriteXMLCacheFile ( $selMediaFile , $cachefilename );

        $percentdone = $percentdone + (100 / $numberofrows);

        $lbxImport->selectionClear($_);
      }
      $mw->update();

   }
   $btnStop->configure( -background=>$darkgray, -foreground=>$lightgray);
   $percentdone=0;
   $mw->Unbusy();
   $mw->update();
   loadImportDirectory();
   loadLibrary();
}

# ----------------------------------------------------------------------------------------------------
sub processSelectedLibraryData ()  {
# ----------------------------------------------------------------------------------------------------

   my $processType =shift;
   my $processVal =shift;

   my @selRows = $lbxLibrary->curselection();
   my $numberofrows = @selRows ;

   $running=1;
   $btnStop->configure( -background=>'red', -foreground=>$offwhite);

   foreach (@selRows ) {

     if ($running==1){

       my @selImportRow = $lbxLibrary->getRow($_);

       my $selMediaFile = $selImportRow[$COL_MEDIAFILE];
       my $thisvcodec =  $selImportRow[$COL_VCODEC];
       my $thisvbitrate =  $selImportRow[$COL_VBITRATE];
       my $thisacodec =  $selImportRow[$COL_ACODEC];
       my $thisabitrate =  $selImportRow[$COL_ABITRATE];
       my $thiscontainer =  $selImportRow[$COL_CONTAINER];
       my $thismaxvol =  $selImportRow[$COL_MAXVOL];
       my $thismeanvol =  $selImportRow[$COL_MEANVOL];
       my $filesize = $selImportRow [$COL_FILESIZE];
       my $timestamp = $selImportRow [$COL_TIMESTAMP];
       my $compressed =  $selImportRow[$COL_COMPRESSED];
       my $normalized =  $selImportRow[$COL_NORMALIZED];
       my $tags =  $selImportRow[$COL_TAGS];
       my $rating =  $selImportRow[$COL_RATING];
       my $weight =  $selImportRow[$COL_WEIGHT];

       my ($bareMediaFile, $barePath) = fileparse ($selMediaFile);

       if ($processType eq "setCData") {
           $compressed =  $processVal;
       }
       if ($processType eq "setNData") {
           $normalized = $processVal;
       }
       if ($processType eq "setRData") {
           $rating = $processVal;
       }
       if ($processType eq "setWData") {
           $weight = $processVal;
       }
       if ($processType eq "setTData") {
           $tags = $processVal ;
       }
       if ($processType eq "addTData") {
           $tags = addTags ( $tags, $processVal) ;
       }
       if ($processType eq "delTData") {
           $tags = delTags ( $tags, $processVal) ;
       }

       print $logfile $processType . " " . $processVal . "\n";

       # generate new cache filename
       my $cachefilename = $cachedir . "/" . $bareMediaFile . ".data";
           $cachefilename =~ s/ /_/gsm;
           writeXMLCacheFile ( 
                                      $cachefilename,
                                      $selMediaFile,
                                      $xml_version,
                                      $thisvcodec , 
                                      $thisvbitrate, 
                                      $thisacodec , 
                                      $thisabitrate, 
                                      $thiscontainer, 
                                      $thismaxvol, 
                                      $thismeanvol, 
                                      $filesize, 
                                      $timestamp,
                                      $compressed,
                                      $normalized,
                                      $tags,
                                      $rating,
                                      $weight );


      # update the mlistbox
      $lbxLibrary ->delete($_);
      $lbxLibrary->insert ($_, [
                                      $selMediaFile,
                                      $tags,
                                      $rating,
                                      $weight,
                                      $thismaxvol, 
                                      $thismeanvol, 
                                      $compressed,
                                      $normalized,
                                      $filesize, 
                                      $timestamp,
                                      $thisvcodec , 
                                      $thisvbitrate, 
                                      $thisacodec , 
                                      $thisabitrate, 
                                      $thiscontainer
                                               ] ) ;
      $lbxLibrary->selectionSet($_);
      

      $percentdone = $percentdone + (100 / $numberofrows);
      $mw->update();


     }   # end of if (running)

   }   # end of loop

   $btnStop->configure( -background=>$darkgray, -foreground=>$lightgray);
   $percentdone = 0;

   # loadLibrary();  # not going to do this anymore

}


# ----------------------------------------------------------------------------------------------------
sub addTags () {
# ----------------------------------------------------------------------------------------------------
   my $prevtags = shift;
   my @prevtag = split ( /\s/, $prevtags );
   my $newtags = shift;
   my @newtag = split ( /\s/, $newtags );

   my $returntags=$prevtags;

   foreach (@newtag) {
       my $matched = 0;
       my $thisnewtag = $_;
       foreach (@prevtag) {
          my $thisprevtag = $_;
          if ( $thisprevtag eq $thisnewtag ) {  
               $matched = 1 ; 
          }
       }
       if ($matched == 0) {
          $returntags = $returntags . " " . $thisnewtag;
       }
   }
   #remove any leading and trailing whitespace
   $returntags =~ s/^\s+|\s+$//g;
   return $returntags;
}



# ----------------------------------------------------------------------------------------------------
sub delTags () {
# ----------------------------------------------------------------------------------------------------

   my $prevtags = shift;
   my @prevtag = split ( /\s/, $prevtags );
   my $newtags = shift;
   my @newtag = split ( /\s/, $newtags );

   my $returntags="";

   foreach (@prevtag) {
       my $matched = 0;
       my $thisprevtag = $_;
       foreach (@newtag) {
          my $thisnewtag = $_;
          if ( $thisprevtag eq $thisnewtag ) {  
               $matched = 1 ; 
          }
       }

       if ($matched == 0) {
          $returntags = $returntags . " " . $thisprevtag;
       }
   }

   #remove any leading and trailing whitespace
   $returntags =~ s/^\s+|\s+$//g;
   return $returntags;
}

my @unsortedPaths;
my @sortedPaths;
my $numberoffiles;

# ----------------------------------------------------------------------------------------------------
sub makePlaylists2 () {
# ----------------------------------------------------------------------------------------------------

    # get directory listing of cache directory
    my @dirListing=`$LS "$cachedir"`;

    #  check for, bail on empty directory listing
 	if (@dirListing==0) {
	     return 1;
	}


    $numberoffiles = $#dirListing + 1;

    $mw->update();

     my $unsortedcount=0;

     #--------------------------------------
     # iterate through directory listing, 
     # read cache files, get xml data, 
     # build new list of data "unsortedPaths"
     #--------------------------------------
     foreach (@dirListing) {
          
        $percentdone = $percentdone + (100 / $numberoffiles);
        $mw->update();

       my $cachefilename=$_;
       chomp($cachefilename);

        my $xmlread = new XML::Simple;
        my $xmlreaddata = $xmlread->XMLin( $cachedir . "/" . $cachefilename, SuppressEmpty => '');

        my $weight =  $xmlreaddata->{weight};

        if ($weight > 0) {
             $unsortedPaths[$unsortedcount]->{file}=$xmlreaddata->{filename};
             $unsortedPaths[$unsortedcount]->{sortable_filename}=$xmlreaddata->{filename};
             $unsortedPaths[$unsortedcount]->{tags}=$xmlreaddata->{tags};
             $unsortedPaths[$unsortedcount++]->{weight}=$xmlreaddata->{weight};
        }

     }
     
     # iterate through unsortedPaths and make the sortable_filename actually
     # sortable, cast all characters to lowercase and add up to three
     # leading zeroes on all numbers.
     foreach (@unsortedPaths) {
             $_->{sortable_filename} = lc ($_->{sortable_filename});
             $_->{sortable_filename} =~ s/([0-9]+)/sprintf('%04d',$1)/ge;
             if ($debug ==1) { print $logfile $_->{file} . " reformats to " . $_->{sortable_filename} . "\n"; }
     }

     # re-sort the list based on the sortable_filename into sortedPaths
     @sortedPaths = sort  { $a->{sortable_filename} cmp $b->{sortable_filename} } @unsortedPaths;


     # iterate through playlist root matrix

     for (my $rcounter=1;$rcounter< $tmxPlaylistRoots->cget('rows');$rcounter++) {

        $playlistroot = $tmxPlaylistRoots->get ("$rcounter,0")  ;
        $playlistoutputpath = $tmxPlaylistRoots->get ("$rcounter,1")  ;

        # iterate through playlist matrix

        for (my $pcounter=1;$pcounter< $tmxPlaylists->cget('rows');$pcounter++) {

           $playlistname =  $tmxPlaylists->get ("$pcounter,0")  ;
           $playlistcount = $tmxPlaylists->get ("$pcounter,1")  ;
           $includeTags = $tmxPlaylists->get ("$pcounter,2")  ;
           $excludeTags = $tmxPlaylists->get ("$pcounter,3")  ;

           makePlaylists();
        
        }

     }
      
}



# ----------------------------------------------------------------------------------------------------
sub makePlaylists () {
# ----------------------------------------------------------------------------------------------------


    my @worklist;
    my $worklistcount=0;
    my @filterlist;
    my @outputlist;

    my $curdirectory="";
    my @curdirectorylist;
    my $curdirectorylistcount=0;
    my $curweight=0;

  #--------------------------------------
  # filter for include tags
  #--------------------------------------
  my @includedTag = split ( /\s/, $includeTags);
  my $arrayIndex=0;
  my $absoluteIndex=0;

  foreach (@sortedPaths) {
      my $thisPath = $_;

      # include everything if $includeTags is empty
      my $isIncluded =1;
   
      if ( $includeTags ne "") {
          $isIncluded =0;

          my $filetags = $thisPath->{tags};
          my @filetag = split (/\s/, $filetags);

          foreach (@includedTag) {
             my $thisTag = $_;
             foreach (@filetag) {
                my $thisFileTag = $_;
                if ($thisFileTag eq $thisTag) {
                   if ($debug == 1) { printf ("%s", $absoluteIndex . ":\t" . $thisFileTag . " matched to " . $thisTag . " \n");}
                   $isIncluded = 1;
                } else {
                   if ($debug == 1) { printf ("%s", $absoluteIndex . ":\t" . $thisFileTag . " does not match " . $thisTag . " \n");}
                }
             }
          }
      }  

      if ($isIncluded == 1) {
        $filterlist[$arrayIndex++]=$thisPath;
      }
      $absoluteIndex++;
  }

  # undefine the @sortedPaths array so that we can re-use it
  # undef @sortedPaths;
  my @excludeFiltered;

  #--------------------------------------
  # filter for exclude tags
  #--------------------------------------
  my @excludedTag = split ( /\s/, $excludeTags);
  $arrayIndex=0;
  $absoluteIndex=0;

  foreach (@filterlist) {
       my $thisPath = $_;

      # include everything if $excludeTags is empty
      my $isExcluded =0;

      if ( $excludeTags ne "") {

          my $filetags = $thisPath->{tags};
          my @filetag = split (/\s/, $filetags);
          foreach (@excludedTag) {
             my $thisTag = $_;
             foreach (@filetag) {
                my $thisFileTag = $_;

                if ($thisFileTag eq $thisTag) {
                   if ($debug == 1) { printf ("%s", $absoluteIndex . ":\t" . $thisFileTag . " matched to " . $thisTag . " \n");}
                   $isExcluded = 1;
                } else {
                   if ($debug == 1) { printf ("%s", $absoluteIndex . ":\t" . $thisFileTag . " does not match " . $thisTag . " \n");}
                }

             }
          }
      }


            if ( $isExcluded == 0 ) {

                if ( $debug ==1){printf ("%s exclude filter: ", $absoluteIndex . ":\t" ."\n" );}
                $excludeFiltered[$arrayIndex++]=$thisPath;

            }

            $absoluteIndex++;
        }

        #--------------------------------------
        # build single long playlist
        #--------------------------------------

        $absoluteIndex = 0;
        (my $temp, $curdirectory) = fileparse( $excludeFiltered[0]->{file});
        foreach (@excludeFiltered) {

               my ($bareMediaFile, $barepath) = fileparse ($_->{file});

               if ($debug == 1) { printf ("%s", "build playlist: " . $barepath . $bareMediaFile . "\n" ); }

               # if the path has changed we are on a new folder
               # OR 
               # we have reached the end of the list:
               #   output the old current working directory list 

               if (($barepath ne $curdirectory) || ( $absoluteIndex+1 == @excludeFiltered )) {
               
                  if ($debug == 1) { printf ("%s", "working directory changed  from " .$curdirectory . " to " . $barepath . "\n" ); }

                  # offset the @curdirectorylist a random number lower than its array count

                  my @shiftedarray;
                  my $randshift =  rand( int ($curdirectorylistcount));

                  for (my $shiftcount =0; $shiftcount < $curdirectorylistcount; $shiftcount ++) {
                       my $thisshift= $randshift + $shiftcount;
                       if ($thisshift > $curdirectorylistcount) {  
                           $thisshift = $thisshift - $curdirectorylistcount;
                       }
                       $shiftedarray[$shiftcount] = $curdirectorylist[$thisshift];
                  }
                  @curdirectorylist = @shiftedarray;

                  # output @curdirectorylist to @worklist $curweight number of times
                  for (my $thispass=0;$thispass<$curweight;$thispass++){

                       # calculate the index position
                       my $itemcount=0;
                       foreach (@curdirectorylist) {
                             # calculate the index position 
                             $curdirectorylist[$itemcount]->{index} = (($arraymax / $curweight) * $thispass) +
                                                                     (($arraymax / $curweight) * ($itemcount / $curdirectorylistcount) );
                             $itemcount++;
                        }

                       foreach (@curdirectorylist) {
                             $worklist[$worklistcount]->{rand} = $_->{index};
                             $worklist[$worklistcount]->{file} = $_->{file};

                             printf $logfile  "worklist count: " . $worklistcount .
                                              "\tindex: " . $worklist[$worklistcount]->{rand}  .
                                              "\tfile: " . $worklist[$worklistcount]->{file} . "\n";

                             $worklistcount++; 
                       }

                   }

                   # empty out the current directory list
                   undef @curdirectorylist;
                   $curdirectorylistcount=0;
                   $curweight=0;
 
                }    # end of unless barepath eq curdirectory 


               # if the file has weight, add the current listing to the current array
               if ( $_->{weight} > 0) {
                  $curdirectorylist[$curdirectorylistcount++]=$_;
               }

               # remember the working directory for the next foreach @dirListing iteration
               $curdirectory = $barepath;

               # remember the highest weight, we will need to know it after the folder changes
               if ($curweight < $_->{weight}) {
                   $curweight = $_->{weight};
               }

              $absoluteIndex++;

        }   

        #--------------------------------------
        # sort the list by the calculated index value (listed as "rand")
        #--------------------------------------
        @outputlist = sort { $a->{rand} <=> $b->{rand} } @worklist;



    my $outputcount = @outputlist;
    my $itemsperlist =  $outputcount / $playlistcount;

    my $currentlist = 1;
    my $currentlistitemcount = 0;

    my $playlistfile = IO::File->new(">" . $workingdirectory . "/playlists/". $playlistoutputpath . "/" . $playlistname . "-" . $currentlist . ".xspf" );

             printf $logfile "Playlist File: " . $workingdirectory . "/playlists/". $playlistoutputpath . "/" . $playlistname . "-" . $currentlist . ".xspf" . "\n";

    my $xmlwriter = XML::Writer->new(OUTPUT => $playlistfile, DATA_MODE => 1, DATA_INDENT=>2);

    $xmlwriter->xmlDecl ( "UTF-8", 1);
    $xmlwriter->startTag("playlist",
                         "xmlns"=>"http://xspf.org/ns/0/",
                         "xmlns:vlc"=>"http://www.videolan.org/vlc/playlist/ns/0/",
                         "version"=>"1"
                         );
    $xmlwriter->startTag("title");
    $xmlwriter->characters(  $playlistname . "-" . $currentlist );
    $xmlwriter->endTag("title");
    $xmlwriter->startTag("trackList");

    foreach (@outputlist) {

       my $thisitem=$_;
       my $thisfile=$thisitem->{file};

       if ($debug == 1) { printf ( "%s", "location to output: " . $thisfile . "\n" ); }
       if ($debug == 1) { printf ( "%s", "   localroot is set to   : " . $workingdirectory . "\n" ); }
       if ($debug == 1) { printf ( "%s", "   playlistroot is set to: " . $playlistroot . "\n" ); }
       $thisfile =~ s/$workingdirectory/$playlistroot/g ;
       if ($debug == 1) { printf ( "%s", "local root changed to: " . $thisfile . "\n" ); }

       $currentlistitemcount++;

       $xmlwriter->startTag("track");

        $xmlwriter->startTag("location");
          $xmlwriter->characters ( $thisfile );
        $xmlwriter->endTag("location");

        #$xmlwriter->startTag("extension",
        #                     "application"=>"http://www.videolan.org/vlc/playlist/0" );
        # $xmlwriter->startTag("vlc:id");
        #  $xmlwriter->characters ( $currentlistitemcount-1 );
        # $xmlwriter->endTag("vlc:id");
        #$xmlwriter->endTag("extension");

       $xmlwriter->endTag("track");

       if ( $currentlistitemcount > $itemsperlist ) {

              $xmlwriter->endTag("trackList");
              $xmlwriter->endTag("playlist");
              $xmlwriter->end();
              $playlistfile->close();

              $currentlist++;
              $currentlistitemcount =0;

              $playlistfile = IO::File->new(">".$workingdirectory . "/playlists/". $playlistoutputpath . "/" . $playlistname . "-" . $currentlist . ".xspf" );
              $xmlwriter = XML::Writer->new(OUTPUT => $playlistfile, DATA_MODE => 1, DATA_INDENT=>2);

              $xmlwriter->xmlDecl ( "UTF-8", 1);
              $xmlwriter->startTag("playlist",
                                  "xmlns"=>"http://xspf.org/ns/0/",
                                  "xmlns:vlc"=>"http://www.videolan.org/vlc/playlist/ns/0/",
                                  "version"=>"1"
                                  );
              $xmlwriter->startTag("title");
              $xmlwriter->characters(  $playlistname . "-" . $currentlist );
              $xmlwriter->endTag("title");
              $xmlwriter->startTag("trackList");
              
       }

    }
 
    $xmlwriter->endTag("trackList");
    $xmlwriter->endTag("playlist");
    $xmlwriter->end();
    $playlistfile->close();

    $percentdone = 0;
    $mw->Unbusy();
    $mw->update();

}



# ----------------------------------------------------------------------------------------------------
sub processSelectedMedia ()  {
# ----------------------------------------------------------------------------------------------------

   my $processType =shift;

   my @selRows = $lbxLibrary->curselection();
   my $numberofrows = @selRows ;

   $running=1;
   $btnStop->configure( -background=>'red', -foreground=>$offwhite);

   $mw->Busy();
   $mw->update();

   foreach (@selRows ) {

     if ($running==1){

       my @selImportRow =  $lbxLibrary->getRow($_);
       my $selMediaFile =  $selImportRow[$COL_MEDIAFILE];
       my $thisvcodec =    $selImportRow[$COL_VCODEC];
       my $thisvbitrate =  $selImportRow[$COL_VBITRATE];
       my $thisacodec =    $selImportRow[$COL_ACODEC];
       my $thisabitrate =  $selImportRow[$COL_ABITRATE];
       my $thiscontainer = $selImportRow[$COL_CONTAINER];
       my $thismaxvol =    $selImportRow[$COL_MAXVOL];
       my $thismeanvol =   $selImportRow[$COL_MEANVOL];
       my $filesize =      $selImportRow[$COL_FILESIZE];
       my $timestamp =     $selImportRow[$COL_TIMESTAMP];
       my $compressed =    $selImportRow[$COL_COMPRESSED];
       my $normalized =    $selImportRow[$COL_NORMALIZED];
       my $tags =          $selImportRow[$COL_TAGS];
       my $rating =        $selImportRow[$COL_RATING];
       my $weight =        $selImportRow[$COL_WEIGHT];

       my ($bareMediaFile, $barePath) = fileparse ($selMediaFile);
       my $outputfile = prepareMediaFilename($bareMediaFile,$thiscontainer);
       my $outputpath = $barePath . $outputfile;

       my $cachefilename;

       # -----------------------------------------------------------------------------------
       if ($processType =~ /compress/ ) {
       # -----------------------------------------------------------------------------------

            # move the original media file to a new filename
            my $newmediafilename = $selMediaFile . ".sav.nocompress" ;
            my $cmdFileMove = $MV . " \"" .  $selMediaFile . "\" \"" .   $newmediafilename . "\"";
            system ($cmdFileMove);


             my $cmdffmpeg = $NICE . " " . $FFMPEG . " -i \"" .  $newmediafilename  . "\" " .
                                   $ffmpegCompressFilter .
                                   " -strict -2 -vcodec copy -b:a " . $thisabitrate . "k" .
                                   " \"" . $outputpath . "\"";

             $statustext = "audio compressing " .  $bareMediaFile;
             $mw->update();
             printf $logfile $cmdffmpeg . "\n";
             system ($cmdffmpeg);


             # figure out the name of, and delete, the old cache file, if it exists
             # original may have already been deleted (upstream)
          	 my $cachefilename = $cachedir . "/" .  $bareMediaFile . ".data";
             $cachefilename =~ s/ /_/gsm;
             if (-e $cachefilename) {
                my $cmdrmcache = $RM . " \"" . $cachefilename . "\"";
                system ( $cmdrmcache);
             }

             # generate new cache filename
	         $cachefilename = $cachedir . "/" . $outputfile . ".data";
             $cachefilename =~ s/ /_/gsm;

             $statustext = "re-analyzing " .  $outputfile;
             $mw->update();

              ( $thiscontainer,
                $thisvcodec, 
                $thisvbitrate,
                $thisacodec,
                $thisabitrate,
                $thismeanvol,
                $thismaxvol,
                $timestamp,
                $filesize )
              = detectMediaProperties ($outputpath );

               $compressed = time();

                writeXMLCacheFile ( 
                                      $cachefilename,
                                      $outputpath,
                                      $xml_version,
                                      $thisvcodec , 
                                      $thisvbitrate, 
                                      $thisacodec , 
                                      $thisabitrate, 
                                      $thiscontainer, 
                                      $thismaxvol, 
                                      $thismeanvol, 
                                      $filesize, 
                                      $timestamp,
                                      $compressed,
                                      $normalized,
                                      $tags,
                                      $rating,
                                      $weight );

              # remember the new file path so that other downstream
              # functions can remember it
              $selMediaFile = $outputpath;
              my ($bareMediaFile, $barePath) = fileparse ($selMediaFile);
              # my $outputfile = prepareMediaFilename($bareMediaFile,$thiscontainer);

             $statustext = "" .  $outputfile;
             $mw->update();

       }  # end of if ~= compress 


       # -----------------------------------------------------------------------------------
       if ($processType =~ /normalize/ ) {
       # -----------------------------------------------------------------------------------

           #calculate normalization
           my $adjustVol = int ( (-5) -  $thismaxvol );

           unless ($adjustVol == 0) {                  # don't normalize good target

              # move the original media file to a new filename
              my $newmediafilename = $selMediaFile . ".sav.nonormalize" ;
              my $cmdFileMove = $MV . " \"" .  $selMediaFile . "\" \"" .   $newmediafilename . "\"";
              system ($cmdFileMove);

              my $cmdffmpeg = $NICE . " " . $FFMPEG . " -i \"" .  $newmediafilename  . "\" " .
                          " -af \"volume=" . $adjustVol . "dB\" " .
                          " -strict -2 -vcodec copy " .
                          " \"" . $outputpath . "\"";

              $statustext = "audio normalizing " .  $bareMediaFile;
              $lblStatus->pack(-side => 'left',-anchor=>'w');
              $mw->update();
              printf $logfile $cmdffmpeg . "\n";
              system ($cmdffmpeg);

              # delete the old cache file
              $cachefilename = $cachedir . "/" .  $bareMediaFile . ".data";
              $cachefilename =~ s/ /_/gsm;
              my $cmdrmcache = $RM . " \"" . $cachefilename . "\"";
              system ( $cmdrmcache);

              # generate new cache filename
    	      $cachefilename = $cachedir . "/" . $outputfile . ".data";
              $cachefilename =~ s/ /_/gsm;

               $statustext = "re-analyzing " .  $outputfile;
               $mw->update();

              ( $thiscontainer,
                $thisvcodec, 
                $thisvbitrate,
                $thisacodec,
                $thisabitrate,
                $thismeanvol,
                $thismaxvol,
                $timestamp,
                $filesize )
              = detectMediaProperties ($outputpath );

           }  else {   # normalization not needed, just update the cache normalize timestamp

              print $logfile "normalization not needed, skipping " . $bareMediaFile . "\n";
    	      $cachefilename = $cachedir . "/" . $outputfile . ".data";
              $cachefilename =~ s/ /_/gsm;

           }


           $normalized = time();

           writeXMLCacheFile ( 
                                   $cachefilename,
                                   $selMediaFile,
                                   $xml_version,
                                   $thisvcodec , 
                                   $thisvbitrate, 
                                   $thisacodec , 
                                   $thisabitrate, 
                                   $thiscontainer, 
                                   $thismaxvol, 
                                   $thismeanvol, 
                                   $filesize, 
                                   $timestamp,
                                   $compressed,
                                   $normalized,
                                   $tags,
                                   $rating,
                                   $weight );

             $statustext = "";
             $mw->update();


          }  # end of if =~ normalize


       # -----------------------------------------------------------------------------------
       if ($processType =~ /crop/ ) {
       # -----------------------------------------------------------------------------------

            # move the original media file to a new filename
            my $newmediafilename = $selMediaFile . ".sav.nocrop" ;
            my $cmdFileMove = $MV . " \"" .  $selMediaFile . "\" \"" .   $newmediafilename . "\"";
            system ($cmdFileMove);

             my $crop_cmd='"crop=' . 
                $crop_width . ":" .
                $crop_height . ":" .
                $crop_x . ":" .
                $crop_y . '"' ;

             my $cmdffmpeg = $NICE . " " . $FFMPEG . " -i \"" .  $newmediafilename  . "\" " .
                                   "-filter:v " . $crop_cmd .
                                   " \"" . $outputpath . "\"";

             $statustext = "cropping " .  $bareMediaFile;
             $mw->update();
             printf $logfile $cmdffmpeg . "\n";
             system ($cmdffmpeg);


             # figure out the name of, and delete, the old cache file, if it exists
             # original may have already been deleted (upstream)
          	 my $cachefilename = $cachedir . "/" .  $bareMediaFile . ".data";
             $cachefilename =~ s/ /_/gsm;
             if (-e $cachefilename) {
                my $cmdrmcache = $RM . " \"" . $cachefilename . "\"";
                system ( $cmdrmcache);
             }

             # generate new cache filename
	         $cachefilename = $cachedir . "/" . $outputfile . ".data";
             $cachefilename =~ s/ /_/gsm;

             $statustext = "re-analyzing " .  $outputfile;
             $mw->update();

              ( $thiscontainer,
                $thisvcodec, 
                $thisvbitrate,
                $thisacodec,
                $thisabitrate,
                $thismeanvol,
                $thismaxvol,
                $timestamp,
                $filesize )
              = detectMediaProperties ($outputpath );

                writeXMLCacheFile ( 
                                      $cachefilename,
                                      $outputpath,
                                      $xml_version,
                                      $thisvcodec , 
                                      $thisvbitrate, 
                                      $thisacodec , 
                                      $thisabitrate, 
                                      $thiscontainer, 
                                      $thismaxvol, 
                                      $thismeanvol, 
                                      $filesize, 
                                      $timestamp,
                                      $compressed,
                                      $normalized,
                                      $tags,
                                      $rating,
                                      $weight );

              # remember the new file path so that other downstream
              # functions can remember it
              $selMediaFile = $outputpath;
              my ($bareMediaFile, $barePath) = fileparse ($selMediaFile);
              # my $outputfile = prepareMediaFilename($bareMediaFile,$thiscontainer);

             $statustext = "" .  $outputfile;
             $mw->update();


       }  # end of if ~= crop


       # -----------------------------------------------------------------------------------
       if ($processType =~ /truncate/ ) {
       # -----------------------------------------------------------------------------------

            # move the original media file to a new filename
            my $newmediafilename = $selMediaFile . ".sav.notruncate" ;
            my $cmdFileMove = $MV . " \"" .  $selMediaFile . "\" \"" .   $newmediafilename . "\"";
            system ($cmdFileMove);


             my $cmdffmpeg = $NICE . " " . $FFMPEG . " -i \"" .  $newmediafilename  . "\" " .
                                   "-vcodec copy -acodec copy -ss 00:00:00.000 -to " . $truncatelength .
                                   " \"" . $outputpath . "\"";

             $statustext = "truncating " .  $bareMediaFile;
             $mw->update();
             printf $logfile $cmdffmpeg . "\n";
             system ($cmdffmpeg);


             # figure out the name of, and delete, the old cache file, if it exists
             # original may have already been deleted (upstream)
          	 my $cachefilename = $cachedir . "/" .  $bareMediaFile . ".data";
             $cachefilename =~ s/ /_/gsm;
             if (-e $cachefilename) {
                my $cmdrmcache = $RM . " \"" . $cachefilename . "\"";
                system ( $cmdrmcache);
             }

             # generate new cache filename
	         $cachefilename = $cachedir . "/" . $outputfile . ".data";
             $cachefilename =~ s/ /_/gsm;

             $statustext = "re-analyzing " .  $outputfile;
             $mw->update();

              ( $thiscontainer,
                $thisvcodec, 
                $thisvbitrate,
                $thisacodec,
                $thisabitrate,
                $thismeanvol,
                $thismaxvol,
                $timestamp,
                $filesize )
              = detectMediaProperties ($outputpath );

                writeXMLCacheFile ( 
                                      $cachefilename,
                                      $outputpath,
                                      $xml_version,
                                      $thisvcodec , 
                                      $thisvbitrate, 
                                      $thisacodec , 
                                      $thisabitrate, 
                                      $thiscontainer, 
                                      $thismaxvol, 
                                      $thismeanvol, 
                                      $filesize, 
                                      $timestamp,
                                      $compressed,
                                      $normalized,
                                      $tags,
                                      $rating,
                                      $weight );

              # remember the new file path so that other downstream
              # functions can remember it
              $selMediaFile = $outputpath;
              my ($bareMediaFile, $barePath) = fileparse ($selMediaFile);
              # my $outputfile = prepareMediaFilename($bareMediaFile,$thiscontainer);

             $statustext = "" .  $outputfile;
             $mw->update();


       }  # end of if ~= truncate





        $percentdone = $percentdone + (100 / $numberofrows);
        $mw->update();


     }   # end of if (running)

   }   # end of loop

   $btnStop->configure( -background=>$darkgray, -foreground=>$lightgray);
   $percentdone = 0;
   $mw->Unbusy();
   $mw->update();
   loadLibrary();

}

    

# ----------------------------------------------------------------------------------------------------
sub loadLibrary (){ 
# ----------------------------------------------------------------------------------------------------


    # remember the scroll position
    my ($scrollchar, $scrollpos) = $lbxLibrary->yview();

    $lbxLibrary->delete(0, 'end');

	# get directory listing of cache directory
	my @dirListing=`$LS "$cachedir"`;
    # empty directory listing
	if (@dirListing==0) {
	     return 1;
	}

    my $numberoffiles = $#dirListing + 1;
    $percentdone=0;
    $mw->Busy();
    $mw->update();

    # first pass of two
    # iterate through directory results and check cache consistency
    if ($fixcache eq "On") {
      $statustext = "Checking Media Library Data";

      foreach (@dirListing) {

         $percentdone = $percentdone + (100 / $numberoffiles);

	     my $cachefilename=$_;
	     chomp($cachefilename);

         my $xmlread = new XML::Simple;
         my $xmlreaddata = $xmlread->XMLin( $cachedir . "/" . $cachefilename, SuppressEmpty => '');

         my $cachemedianame= $xmlreaddata->{filename};
         my $cachefilesize=  $xmlreaddata->{filesize};
         my $cachetimestamp=  $xmlreaddata->{timestamp};

         # detect and offer to remove orphaned cache files
         unless ( -e $cachemedianame) {
              # media file does not exist but cache data does

              if ($alwaysDeleteOrphanCache ==1) {
                    my $cmdrm = $RM . " " . "\"" . $cachedir . "/" . $cachefilename . "\"";
                    system ($cmdrm);
              } else {
                   my $d = $mw->DialogBox(-title => "Media File Not Found",  -buttons => ["Always", "Yes","No"]);
                   my $msgtext = $d->add("Label", -text=>"Media file\n" . 
                                                          $cachemedianame . 
                                                          "\nnot found.\nDelete stored data from library?")->pack();
                   my $response = $d->Show;
                   if ($response eq "Always") {  $alwaysDeleteOrphanCache=1; $response="Yes"; }
                   if ($response eq "Yes") { 
                      my $cmdrm = $RM . " " . "\"" . $cachedir . "/" . $cachefilename . "\"";
                      system ($cmdrm);
                   }
              }

         } else  { 

             # get the media file timestamp
             my $mediatimestamp = (stat($cachemedianame))[9];

             # get the media file size
             my $mediafilesize = (stat($cachemedianame))[7];

             unless (( $mediatimestamp == $cachetimestamp ) && ($mediafilesize == $cachefilesize)) {

              if ($alwaysUpdateMediaData ==1) {
                     makeAndWriteXMLCacheFile ( $cachemedianame, $cachefilename);
              } else {

                  my $d = $mw->DialogBox(-title => "Media File Has Changed",  -buttons => ["Always", "Yes","No"]);
                  my $msgtext = $d->add("Label", -text=>"Media file has changed\n" . 
                                                       "Media file " .  $cachemedianame . "\n" .
                                                       "Old timestamp " . $cachetimestamp . " New timestamp " . $mediatimestamp . "\n" .
                                                       "Old filesize " . $cachefilesize . " New filesize " . $mediafilesize . "\n" .
                                                       "Generate new data?")->pack();

                  my $response = $d->Show;
                  if ($response eq "Always") {  $alwaysUpdateMediaData=1; $response="Yes"; }
                  if ($response eq "Yes" ) { 
                     makeAndWriteXMLCacheFile ( $cachemedianame, $cachefilename);
                  }

               }

             } 
         }
      }        #end of foreach @dirlist
    }       # end of if $fixcache

    
    # second pass of two
    # load listbox from cache files
	# get directory listing of cache directory

	@dirListing=`$LS "$cachedir"`;
    # empty directory listing
	if (@dirListing==0) {
	     return 1;
	}

    $statustext = "Loading Media Library Data";
    $numberoffiles = $#dirListing + 1;
    $percentdone=0;
    $mw->update();

    foreach (@dirListing) {

         $percentdone = $percentdone + (100 / $numberoffiles);

	     my $cachefilename=$_;
	     chomp($cachefilename);

         my $xmlread = new XML::Simple;
         my $xmlreaddata = $xmlread->XMLin($cachedir . "/" .$cachefilename, SuppressEmpty => '');

         my $xmlwriteneeded = 0;

         my $cacheversion;
         my $cachemedianame= $xmlreaddata->{filename};
         my $cachecontainer= $xmlreaddata->{container};
         my $cachevcodec= $xmlreaddata->{videocodec};
         my $cachevbitrate= $xmlreaddata->{videobitrate};
         my $cacheacodec= $xmlreaddata->{audiocodec};
         my $cacheabitrate= $xmlreaddata->{audiobitrate};
         my $cachemaxvol= $xmlreaddata->{maxvol};
         my $cachemeanvol= $xmlreaddata->{meanvol};
         my $cachefilesize=  $xmlreaddata->{filesize};
         my $cachetimestamp=  $xmlreaddata->{timestamp};
         my $lastcompressed;
         my $lastnormalized;
         my $tags;
         my $rating;
         my $weight;
         my $sortable_filename = lc ($xmlreaddata->{filename});
         $sortable_filename =~ s/([0-9]+)/sprintf('%04d',$1)/ge;

         unless (exists ($xmlreaddata->{version})) {
             # version not yet defined (first version), set at current version 
             $cacheversion = $xml_version;

             # define new columns
             $lastcompressed =  time();
             $lastnormalized = time();
             $tags =  "";
             $rating = 0;
             $weight = 0;
             $xmlwriteneeded = 1;
             
         } else {
             $cacheversion =  $xmlreaddata->{version};
             $lastcompressed =  $xmlreaddata->{compressed};
             $lastnormalized =  $xmlreaddata->{normalized};
             $tags =  $xmlreaddata->{tags};
             $rating =  $xmlreaddata->{rating};
             $weight =  $xmlreaddata->{weight};
         }


         if ($xmlwriteneeded ==1 ) { writeXMLCacheFile ( 
                                      $cachefilename,
                                      $cachemedianame,
                                      $cacheversion,
                                      $cachevcodec , 
                                      $cachevbitrate, 
                                      $cacheacodec , 
                                      $cacheabitrate, 
                                      $cachecontainer, 
                                      $cachemaxvol, 
                                      $cachemeanvol, 
                                      $cachefilesize, 
                                      $cachetimestamp,
                                      $lastcompressed,
                                      $lastnormalized,
                                      $tags,
                                      $rating,
                                      $weight );   }


         $lbxLibrary->insert ('end', [
                                      $cachemedianame ,
                                      $tags,
                                      $rating,
                                      $weight,
                                      $cachemaxvol, 
                                      $cachemeanvol, 
                                      $lastcompressed,
                                      $lastnormalized,
                                      $cachefilesize, 
                                      $cachetimestamp,
                                      $cachevcodec , 
                                      $cachevbitrate, 
                                      $cacheacodec , 
                                      $cacheabitrate, 
                                      $cachecontainer,
                                      $sortable_filename
                                               ] ) ;

         $lbxLibrary->pack(-side=>'left',-expand => 1,-fill => 'both');
    }
    

    $lbxLibrary->sort(15);
    $percentdone=0;
    $mw->Unbusy();
    $mw->update();
    $statustext = "Ready";
    #$lblStatus->pack(-side => 'left',-anchor=>'w');

    # restore scroll position
    if ($scrollpos ==1 ) {
          $lbxLibrary->yview (moveto=> $scrollpos);
    } else {
          $lbxLibrary->yview (moveto=> $scrollchar);
    }

}



# ----------------------------------------------------------------------------------------------------
sub loadImportDirectory(){
# ----------------------------------------------------------------------------------------------------

    $statustext = "Loading Import Directory";

    $lbxImport->delete(0, 'end');
    $lbxImported->delete(0, 'end');
    $lbxImportSkip->delete(0, 'end');

    if (!(-d $workingdirectory)) {
        if ( -e $workingdirectory ) {
            die $workingdirectory . " is a file not a directory.\n";
        } else {
            die $workingdirectory . " does not exist.\n";
        }
    }

	  
	# get directory listing 
    $statustext = "Getting Directory Listing";
	# my @dirListing=`$LS "$workingdirectory" | $SORT`;
	my @dirListing=`$FIND -H "$workingdirectory" -type f | $SORT ` ;
    # empty directory listing
	if (@dirListing==0) {
	     return 1;
	}

    $percentdone=0;
    $mw->Busy();
    $mw->update();

    my $numberoffiles = $#dirListing + 1;
    $running = 1;


    # iterate through directory results 
    $statustext = "Iterating through Directory Results";
    foreach (@dirListing) {

      if ($running){

         # input filepath, trim off any returns at the end
	     my $mediafile=$_;
	     chomp($mediafile);

          my ($bareMediaFile, $barePath) = fileparse ($mediafile);

          unless (-e $barePath . "/.derange.ignore" ) {

		 my $isAMediaFile=0;

			 if ($mediafile =~ /.webm/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.WEBM/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.mp4/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.MP4/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.m4v/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.M4V/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.avi/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.AVI/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.flv/) { $isAMediaFile=1; }
			 if ($mediafile =~ /.FLV/) { $isAMediaFile=1; }

			 $percentdone = $percentdone + (100 / $numberoffiles);
			 # $statustext = "loading " . $mediafile;
			 $mw->update();


			 if ($isAMediaFile ==1) {


			     # generate a cache file name, replace spaces with underscores
					 my $cachefilename = $cachedir . "/" . $bareMediaFile . ".data";
			     $cachefilename =~ s/ /_/gsm;

			     # if the cache file already exists
			     if (-e $  cachefilename) {
				   readXMLCacheFileImport ( $cachefilename );

			     } else {
					 # cache file does not exist
				   $lbxImport->insert ('end', [  $mediafile  ]);

			     }

			 } else {
			      # $lbxImportSkip->insert ('end', [ $mediafile  ]);
			 }

		  }
         }

  }

  $percentdone=0;
  $mw->Unbusy();
  $mw->update();

  $statustext = "Ready";
  $lblStatus->pack(-side => 'left',-anchor=>'w');

}



# ----------------------------------------------------------------------------------------------------
sub readXMLCacheFileImport () {
# ----------------------------------------------------------------------------------------------------

               my $thisCacheFile=shift;

               my $xmlread = new XML::Simple;
               my $xmlreaddata = $xmlread->XMLin($thisCacheFile, SuppressEmpty => '');

               my $thisfilename= $xmlreaddata->{filename};
               my $thiscontainer= $xmlreaddata->{container};
               my $thisvcodec= $xmlreaddata->{videocodec};
               my $thisvbitrate= $xmlreaddata->{videobitrate};
               my $thisacodec= $xmlreaddata->{audiocodec};
               my $thisabitrate= $xmlreaddata->{audiobitrate};
               my $thismaxvol= $xmlreaddata->{maxvol};
               my $thismeanvol= $xmlreaddata->{meanvol};
               my $thisfilesize=  $xmlreaddata->{filesize};
               my $thistimestamp=  $xmlreaddata->{timestamp};

               # $lbxImported->insert ('end', [ $thisfilename ] ) ;

}



# ----------------------------------------------------------------------------------------------------
sub detectMediaProperties () {
# ----------------------------------------------------------------------------------------------------

               my $thisMediaFile=shift;
    
				#my $detectCommand = $FFPROBE . " \"" . $thisMediaFile . "\" > " . $tempfile . " 2>&1";
				my $detectCommand = $NICE . " " . $FFMPEG . " -i \"" . $thisMediaFile . "\" -af \"volumedetect\" -f null /dev/null > " . $tempfile . " 2>&1";

				system ($detectCommand);
            print $logfile $detectCommand . "\n";

                # grep for lines with the string "Input #0"
                my $grepcommand = $GREP . " -a \"Input #0\" " .  $tempfile;
                my @containerstr = `$grepcommand`;

                # split the string and take the second word from this line, 
                # it is the media container type
                my $container = ( split ' ', $containerstr[0] )[2];

                # grep for lines with the string "Video:"
                my @videostream = `$GREP -a "Video:" $tempfile`;

                # regex search for the word after the string "Video:"
                # which is the video codec
                $videostream[0] =~ /(?<=\bVideo:\s)(\w+)/;
                my $videocodec=$1;

                # regex search for the word before the string "kb/s"
                # which is the video bitrate 
                $videostream[0] =~ /(\S+)\s*kb\/s\s*/;
                my $videobitrate=$1 ;

                # grep for lines with the string "Audio:"
                my @audiostream = `$GREP -a "Audio:" $tempfile`;

                # regex search for the word after the string "Audio:"
                # which is the audio codec
                $audiostream[0] =~ /(?<=\bAudio:\s)(\w+)/;
                my $audiocodec=$1;

                # regex search for the word before the string "kb/s"
                # which is the audio bitrate 
                $audiostream[0] =~ /(\S+)\s*kb\/s\s*/;
                my $audiobitrate=$1 ;

                my $meanvolstr = `$GREP -a mean_volume $tempfile`;
                # -2 is second to last in array, -1 is last 
                my $meanvol = ( split ' ', $meanvolstr )[-2];

                my $maxvolstr = `$GREP -a max_volume $tempfile`;
                # -2 is second to last in array, -1 is last 
                my $maxvol = ( split ' ', $maxvolstr )[-2];  

                # get the media file timestamp
                my $timestamp = (stat($thisMediaFile))[9];

                # get the media file size
                my $filesize = (stat($thisMediaFile))[7];


                return ( $container,
                         $videocodec, 
                         $videobitrate,
                         $audiocodec,
                         $audiobitrate,
                         $meanvol,
                         $maxvol,
                         $timestamp,
                         $filesize );
}



sub makeAndWriteXMLCacheFile () {

               my $thisMediaFile=shift;
               my $thisCacheFile=shift;
    
				#my $detectCommand = $FFPROBE . " \"" . $thisMediaFile . "\" > " . $tempfile . " 2>&1";
				my $detectCommand = $NICE . " " . $FFMPEG . " -i \"" . $thisMediaFile . "\" -af \"volumedetect\" -f null /dev/null > " . $tempfile . " 2>&1";

				system ($detectCommand);
            print $logfile $detectCommand . "\n";

                # grep for lines with the string "Input #0"
                my $grepcommand = $GREP . " -a \"Input #0\" " .  $tempfile;
                my @containerstr = `$grepcommand`;

                # split the string and take the second word from this line, 
                # it is the media container type
                my $container = ( split ' ', $containerstr[0] )[2];

                # grep for lines with the string "Video:"
                my @videostream = `$GREP -a "Video:" $tempfile`;

                # regex search for the word after the string "Video:"
                # which is the video codec
                $videostream[0] =~ /(?<=\bVideo:\s)(\w+)/;
                my $videocodec=$1;

                # regex search for the word before the string "kb/s"
                # which is the video bitrate 
                $videostream[0] =~ /(\S+)\s*kb\/s\s*/;
                my $videobitrate=$1 ;

                # grep for lines with the string "Audio:"
                my @audiostream = `$GREP -a "Audio:" $tempfile`;

                # regex search for the word after the string "Audio:"
                # which is the audio codec
                $audiostream[0] =~ /(?<=\bAudio:\s)(\w+)/;
                my $audiocodec=$1;

                # regex search for the word before the string "kb/s"
                # which is the audio bitrate 
                $audiostream[0] =~ /(\S+)\s*kb\/s\s*/;
                my $audiobitrate=$1 ;

                my $meanvolstr = `$GREP -a mean_volume $tempfile`;
                # -2 is second to last in array, -1 is last 
                my $meanvol = ( split ' ', $meanvolstr )[-2];

                my $maxvolstr = `$GREP -a max_volume $tempfile`;
                # -2 is second to last in array, -1 is last 
                my $maxvol = ( split ' ', $maxvolstr )[-2];  

                # get the media file timestamp
                my $timestamp = (stat($thisMediaFile))[9];

                # get the media file size
                my $filesize = (stat($thisMediaFile))[7];


                writeXMLCacheFile ( 
                                      $thisCacheFile,
                                      $thisMediaFile,
                                      $xml_version,
                                      $videocodec , 
                                      $videobitrate, 
                                      $audiocodec , 
                                      $audiobitrate, 
                                      $container, 
                                      $maxvol, 
                                      $meanvol, 
                                      $filesize, 
                                      $timestamp,
                                      0,
                                      0,
                                      "",
                                      0,
                                      0 );  


}

# ----------------------------------------------------------------------------------------------------
sub saveAndExit(){
# ----------------------------------------------------------------------------------------------------
   # save working directory to config file

   $cfg->param("derange.FixCache", $fixcache );
   $cfg->param("derange.Geometry", $mw->geometry() );
   $cfg->param("derange.PlayListLocalRoot", $localroot);
   $cfg->param("derange.RenameFiles", $renamefiles );
   $cfg->param("derange.WorkingDirectory", $workingdirectory);

   $cfg->write();

   savePlaylistXMLfile();
   
   exit;
}


# ----------------------------------------------------------------------------------------------------
sub verifyDir() {
# ----------------------------------------------------------------------------------------------------
  my $dirToCheck = shift;
  unless ( -d $dirToCheck ) {
    # directory does not exist, create it.
     print $logfile "\ncreating directory " . $dirToCheck . " \n";
     `$MKDIR $dirToCheck`;
      unless ( -d $dirToCheck ) {
          die "could not create directory " . $dirToCheck . " \n";
      }
   }
}

# ----------------------------------------------------------------------------------------------------
sub verifyFile() {
# ----------------------------------------------------------------------------------------------------
  my $fileToCheck = shift;
  unless ( -f $fileToCheck ) {
    # file does not exist, touch it.
     print $logfile "\ncreating file " . $fileToCheck . " \n";
     `$TOUCH $fileToCheck`;
      unless ( -f $fileToCheck ) {
          die "could not create file " . $fileToCheck . " \n";
      }
	  return 0;
   } else {
      return 1;
   }
}


# ----------------------------------------------------------------------------------------------------
sub prepareMediaFilename(){
# ----------------------------------------------------------------------------------------------------

   my $originalfilename=shift;
   my $mediacontainer=shift;

   $originalfilename =~ s/ /_/g;

   # strip out the following strings from the output filename
   $originalfilename =~ s/_medium//i;
   $originalfilename =~ s/_small//i;
   $originalfilename =~ s/\.mp4//i;
   $originalfilename =~ s/\.m4v//i;
   $originalfilename =~ s/\.avi//i;
   $originalfilename =~ s/\.flv//i;

   if ( $mediacontainer =~ /mp4/i ) { $originalfilename = $originalfilename . ".mp4"; }
   if ( $mediacontainer =~ /avi/i ) { $originalfilename = $originalfilename . ".avi"; }
   if ( $mediacontainer =~ /flv/i ) { $originalfilename = $originalfilename . ".flv"; }

   return $originalfilename;

}


# ----------------------------------------------------------------------------------------------------
sub writeXMLCacheFile (){ 
# ----------------------------------------------------------------------------------------------------

            my $cachefile = shift;
            print $logfile "writing cache file to ". $cachefile . "\n";

            my $medianame = shift;
            my $version = shift;
            my $vcodec  = shift;
            my $vbitrate  = shift;
            my $acodec  = shift;
            my $abitrate = shift;
            my $container = shift;
            my $maxvol = shift;
            my $meanvol = shift;
            my $filesize  = shift;
            my $timestamp = shift;
            my $lastcompressed = shift;
            my $lastnormalized = shift;
            my $tags = shift;
            my $rating = shift;
            my $weight = shift;

            #remove any leading and trailing whitespace from tags
            $tags =~ s/^\s+|\s+$//g;

                 my $xmlfile = IO::File->new(">".$cachefile);
                 my $xmlwriter = XML::Writer->new(OUTPUT => $xmlfile, DATA_MODE => 1, DATA_INDENT=>2);

                 $xmlwriter->startTag("cachedata");

                 $xmlwriter->startTag("version");
                 $xmlwriter->characters ( $version );
                 $xmlwriter->endTag("version");

                 $xmlwriter->startTag("filename");
                 $xmlwriter->characters ( $medianame );
                 $xmlwriter->endTag("filename");

                 $xmlwriter->startTag("timestamp");
                 $xmlwriter->characters ( $timestamp );
                 $xmlwriter->endTag("timestamp");

                 $xmlwriter->startTag("filesize");
                 $xmlwriter->characters ( $filesize );
                 $xmlwriter->endTag("filesize");

                 $xmlwriter->startTag("container");
                 $xmlwriter->characters ( $container );
                 $xmlwriter->endTag("container");

                 $xmlwriter->startTag("videocodec");
                 $xmlwriter->characters ( $vcodec );
                 $xmlwriter->endTag("videocodec");

                 $xmlwriter->startTag("videobitrate");
                 $xmlwriter->characters ( $vbitrate );
                 $xmlwriter->endTag("videobitrate");

                 $xmlwriter->startTag("audiocodec");
                 $xmlwriter->characters ( $acodec );
                 $xmlwriter->endTag("audiocodec");

                 $xmlwriter->startTag("audiobitrate");
                 $xmlwriter->characters ( $abitrate );
                 $xmlwriter->endTag("audiobitrate");

                 $xmlwriter->startTag("meanvol");
                 $xmlwriter->characters ( $meanvol );
                 $xmlwriter->endTag("meanvol");

                 $xmlwriter->startTag("maxvol");
                 $xmlwriter->characters ( $maxvol );
                 $xmlwriter->endTag("maxvol");

                 $xmlwriter->startTag("compressed");
                 $xmlwriter->characters ( $lastcompressed );
                 $xmlwriter->endTag("compressed");

                 $xmlwriter->startTag("normalized");
                 $xmlwriter->characters ( $lastnormalized );
                 $xmlwriter->endTag("normalized");

                 $xmlwriter->startTag("tags");
                 $xmlwriter->characters ( $tags );
                 $xmlwriter->endTag("tags");

                 $xmlwriter->startTag("rating");
                 $xmlwriter->characters ( $rating );
                 $xmlwriter->endTag("rating");

                 $xmlwriter->startTag("weight");
                 $xmlwriter->characters ( $weight );
                 $xmlwriter->endTag("weight");

                 $xmlwriter->endTag("cachedata");

                 $xmlwriter->end();
                 $xmlfile->close();

}

sub savePlaylistXMLfile() {

  my $playxmlfile = IO::File->new(">".$playlistconfigfile);
  my $playxmlwriter = XML::Writer->new(OUTPUT => $playxmlfile, DATA_MODE => 1, DATA_INDENT=>2);

  $playxmlwriter->startTag("playlists");

  for (my $counter=1;$counter< $tmxPlaylists->cget('rows');$counter++) {

     $playxmlwriter->startTag("playlist");

     $playxmlwriter->startTag("name");
     $playxmlwriter->characters ( $tmxPlaylists->get ("$counter,0")  );
     $playxmlwriter->endTag("name");
  
     $playxmlwriter->startTag("count");
     $playxmlwriter->characters ( $tmxPlaylists->get ("$counter,1")  );
     $playxmlwriter->endTag("count");
  
     $playxmlwriter->startTag("include");
     $playxmlwriter->characters ( $tmxPlaylists->get ("$counter,2")  );
     $playxmlwriter->endTag("include");
  
     $playxmlwriter->startTag("exclude");
     $playxmlwriter->characters ( $tmxPlaylists->get ("$counter,3")  );
     $playxmlwriter->endTag("exclude");
  
     $playxmlwriter->endTag("playlist");

  }


  for (my $counter=1;$counter< $tmxPlaylistRoots->cget('rows');$counter++) {

     $playxmlwriter->startTag("listroot");

     $playxmlwriter->startTag("root");
     $playxmlwriter->characters ( $tmxPlaylistRoots->get ("$counter,0")  );
     $playxmlwriter->endTag("root");
  
     $playxmlwriter->startTag("output_path");
     $playxmlwriter->characters ( $tmxPlaylistRoots->get ("$counter,1")  );
     $playxmlwriter->endTag("output_path");
  
     $playxmlwriter->endTag("listroot");

  }


  $playxmlwriter->endTag("playlists");

  $playxmlwriter->end();
  $playxmlfile->close();
}

