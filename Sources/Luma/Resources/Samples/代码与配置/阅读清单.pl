use strict;
use warnings;
use utf8;
binmode STDOUT, ':encoding(UTF-8)';

my @titles = ('设计文档', '实验记录');
for my $title (@titles) {
    print "继续阅读：$title\n";
}
