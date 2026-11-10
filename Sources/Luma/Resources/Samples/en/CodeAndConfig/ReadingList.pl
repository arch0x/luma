use strict;
use warnings;
use utf8;
binmode STDOUT, ':encoding(UTF-8)';

my @titles = ('Design notes', 'Lab notes');
for my $title (@titles) {
    print "Continue reading: $title\n";
}
