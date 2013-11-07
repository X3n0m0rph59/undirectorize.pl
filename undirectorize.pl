#!/usr/bin/perl -w

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#Author: X3n0m0rph59@gmail.com

use strict;
use warnings;
use 5.018;
use English;

use Getopt::Long qw(:config no_ignore_case bundling);
use Term::ANSIColor qw(:constants);
use File::Basename;
use File::Copy;

# global constants
use constant NAME    => "undirectorize.pl";
use constant VERSION => "0.1";

# booleans
use constant TRUE  => 1;
use constant FALSE => 0;

# global variables
# act on files with the following extensions
my @extensions = ('\.avi$', '\.mkv$', '\.mp?g$', '\.mp4$', '\.mov$');
#my @extension_re = (m/\.avi$/i, m/\.mkv$/i, m/\.mp?g$/i, m/\.mp4$/i, m/\.mov$/i);

my $interrupted = FALSE;
my $waiting_for_input = FALSE;

# command line flags
my $dry_run = FALSE;
my $interactive_mode = FALSE;
my $verbosity = 0;
my $print_help = FALSE;
my $print_version = FALSE;



# print_usage() - Display help text
#
sub print_usage() {
    print BOLD, BRIGHT_WHITE, NAME, RESET;

    print " - Recursively rename video files to the name of the directory they reside in\n";
    print 'Author: X3n0m0rph59@gmail.com',"\n\n";

    print "Usage: ", BOLD, BRIGHT_WHITE, NAME, RESET, " [OPTION]... ", BOLD, BRIGHT_WHITE, "DIRECTORY...", RESET, "\n\n",
          BOLD, "Misc Options\n\n", RESET,
          "\t-n, --dry-run\t\tDon't actually rename anything\n",
          "\t-i, --interactive\tInteractive mode [default]\n",
          "\t-v, --verbose\t\tBe verbose, multiple -v options increase verbosity (up to -vvv)\n",
          BOLD, "\nHelp and Version\n\n", RESET,
          "\t-h, --help\t\tDisplay this short help text\n",
          "\t-V, --version\t\tDisplay version information\n",
          "\n";
}


# print_version()
#
sub print_version() {
    print BOLD, WHITE, NAME, " - Version: ", VERSION, RESET, "\n";
}


# parse_cmd_line()
#
sub parse_cmd_line() {
    # set default options
    my $errors_present = 0;

    my $result = GetOptions('dry-run|n'      => \$dry_run,
                            'interactive|i'  => \$interactive_mode,
                            'verbose|v+'     => \$verbosity,
                            'help|h'         => \$print_help,
                            'version|V'      => \$print_version);

    # use the remainder of the command line as directory names
    our @dir_names = @ARGV;

    #
    # help and version
    if ($print_help) {
        print_usage();

        exit(0);

    } elsif ($print_version) {
        print_version();

        exit(0);
    }


    # check options for validity
    #
    # implied options
    if ($interactive_mode && $verbosity == 0) {
      $verbosity++;
    }
      

    # check validity of dir parameters
    if (!@dir_names) {
        print BOLD, BRIGHT_RED, "[ERROR]: Please specify a directory name\n", RESET;

        print_usage();

        exit(-1);
    }

    # check accessibility of specified directories
    foreach my $dir_name (@dir_names) {
        if (!-d $dir_name) {
            $errors_present++;
            print BOLD, BRIGHT_RED, "[ERROR]: \"$dir_name\" is not a directory: $!\n", RESET;
        }
    }

    # finally, exit if errors occured
    if ($errors_present) {
        print BOLD, BRIGHT_RED, "[ERROR]: Total errors: $errors_present, Exiting now\n", RESET;
        exit(-2);
    }
}


# find_matching_files_in_dir
#
sub find_matching_files_in_dir {
    my $dir_name = shift;
    my $files_skipped = shift;

    my $result = opendir(my $handle, $dir_name);

    if (!$result)
    {
        print "$!\n";
        return FALSE;
    }

    # my @entries = grep { /^\./ && -f "$dir_name/$_" } readdir($handle);
    #

    my @entries;

    ENTRY: while (my $entry = readdir $handle) {
        last ENTRY if $interrupted;

        next ENTRY if ($entry eq "." || $entry eq "..");
        next ENTRY if !-f "$dir_name/$entry";

        MATCH: foreach my $extension (@extensions) {
            if ($entry =~ m/$extension/i) {
                push(@entries, $entry);

                print BOLD, BRIGHT_GREEN, "[INFO]: Found file \"$entry\"\n", RESET unless $verbosity < 3;
                
                last MATCH;

            } else {
                $$files_skipped++;

                print BOLD, BRIGHT_YELLOW, "[WARN]: Skipped file \"$entry\" (Reason: non matching extension)\n", RESET unless $verbosity < 3;

                last MATCH;
            }
        }

        # ~~ smart match is still/again experimental in perl 5.18
        # push(@entries, $entry) if $entry ~~ @extension_re;
    }


    closedir $handle;

    return @entries;
}


# process_directory
#
sub process_directory {
    my $dir_name = shift;

    my $files_renamed = 0;
    my ($files_skipped, $errors) = (0, 0);

    my $result = opendir(my $handle, $dir_name);

    if (!$result)
    {
        print "$!\n";
        return FALSE;
    }

    print BOLD, BRIGHT_YELLOW, "[INFO]: Enumerating directory \"$dir_name\"\n", RESET unless $verbosity < 3;

    ENTRY: while (my $entry = readdir($handle)) {
        last ENTRY if $interrupted;

        next ENTRY if ($entry eq "." || $entry eq "..");
        next ENTRY if !-d "$dir_name/$entry";

        my @files = find_matching_files_in_dir("$dir_name/$entry", \$files_skipped);

        FILE: for (my $cnt = 0; $cnt <= $#files; $cnt++) {

            my ($filename, $directories, $suffix) = fileparse($files[$cnt], qr/\.[^.]*/);

            # set up source and dest paths
            my $src_file = "$dir_name/$entry/$files[$cnt]";

            # if we have multiple files in a directory add a "_part#" suffix
            my $dst_file = undef;
            if ($#files > 0) {
               $dst_file = "$dir_name/${entry}_part$cnt$suffix";

               print BOLD, BRIGHT_YELLOW, "[INFO]: Renaming ", BRIGHT_WHITE, "\"$dir_name/$entry/", BOLD, BRIGHT_YELLOW, "$files[$cnt]\"",
                     BRIGHT_WHITE, " -> \"$dir_name/", BRIGHT_GREEN, "$dir_name/${entry}_part$cnt$suffix\"\n", RESET unless $verbosity < 1;

            } else {
               $dst_file = "$dir_name/$entry$suffix";

               print BOLD, BRIGHT_YELLOW, "[INFO]: Renaming ", BRIGHT_WHITE, "\"$dir_name/$entry/", BOLD, BRIGHT_YELLOW, "$files[$cnt]\"",
                     BRIGHT_WHITE, " -> \"$dir_name/", BRIGHT_GREEN, "$entry$suffix\"\n", RESET unless $verbosity < 1;
            }


            if (!$dry_run) {
               if ($interactive_mode)
               {                  
                  READCHR: {
                     print "Rename file? (Ctrl+c to quit) [", BOLD, BRIGHT_WHITE, "Y", RESET, "/n]: ";
                     
                     $waiting_for_input++;
                     my $input = <STDIN>;
                     $waiting_for_input--;

                     last ENTRY if $interrupted;

                     chomp $input;
                     $input = lc $input;

                     if ($input eq "n") {
                        $files_skipped++;
                     
                        print BOLD, BRIGHT_YELLOW, "[INFO]: Skipped file: ", BRIGHT_WHITE, "\"$dir_name/$entry/", BOLD, BRIGHT_YELLOW, "$files[$cnt]\"\n", RESET unless $verbosity < 1;

                        next FILE;
                        
                     } elsif ($input ne "y" && $input ne "") {

                        print BOLD, BRIGHT_RED, "[ERROR]: Invalid input\n", RESET;                        
                        
                        redo READCHR;
                     }
                  }
               }

               $result = move ($src_file, $dst_file);

               if (!$result)
               {
                  $errors++;
                  print BOLD, BRIGHT_RED, "[ERROR]: $!\n", RESET;
               }
            }

            $files_renamed++;
        }

    }

    closedir $handle;

    return ($files_renamed, $files_skipped, $errors);
}


# interrupt handler
#  SIGINT
#
sub interrupt() {
   $interrupted++;

   print BOLD, BRIGHT_RED, "\nExiting on user interrupt\n", RESET;
   
   if ($waiting_for_input) {   
      exit(0);
   }
}


# Main program starts here
#
parse_cmd_line();

our @dir_names;
our $total_errors = 0;

# set  up signal handlers
$SIG{INT} = \&interrupt;

if ($dry_run) {
   print BOLD, BRIGHT_YELLOW, "[INFO]: ** Dry run ** - Not renaming anything\n", RESET unless $verbosity < 1;
}

foreach my $dir_name (@dir_names) {
    print BOLD, BRIGHT_YELLOW, "[INFO]: Processing directory \"$dir_name\"\n", RESET unless $verbosity < 2;

    my ($files_renamed, $files_skipped, $errors) = process_directory($dir_name);

    if ($errors) {
        print BOLD, BRIGHT_RED, "\n[ERROR]: #Errors: $errors, #Files renamed: $files_renamed, #Files skipped: $files_skipped\n", RESET; # unless $verbosity < 1;
    } else {
        print BOLD, BRIGHT_GREEN, "\n[SUCCESS]: #Files renamed: $files_renamed, #Files skipped: $files_skipped\n", RESET unless $verbosity < 1;
    }

    $total_errors += $errors;
}

exit($total_errors);
