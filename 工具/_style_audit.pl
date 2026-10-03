use strict; use warnings; use utf8; use Encode;
binmode STDOUT, ":utf8"; binmode STDERR, ":utf8";

# 翻译腔体检：统计各类"英式中文"标记的出现率
my ($file, $label, $minlen) = @ARGV;
$label //= $file;
$minlen //= 0;

open(my $fh, "<:encoding(UTF-8)", $file) or die "$file: $!";
my @rows;
while (my $l = <$fh>) {
    chomp $l; $l =~ s/\r$//;
    next if $l eq '';
    my @c = split /\t/, $l, -1;
    next if @c < 2;
    my $zh = $c[1];
    next if $zh eq '';
    next unless $zh =~ /[\x{4e00}-\x{9fff}]/;
    next if length($zh) < $minlen;
    push @rows, $zh;
}
close $fh;
my $n = scalar @rows;
print "=== $label （样本 $n 条）===\n\n";

my @pats = (
  ['被动式（被/受到/遭受）',              qr/(?:被[\x{4e00}-\x{9fff}])|受到|遭受/],
  ['代词复数（我们/你们/他们/它们/咱们）', qr/我们|你们|他们|她们|它们|咱们/],
  ['轻动词（进行/作出/给予/予以/加以）',   qr/进行|作出|给予|予以|加以/],
  ['连词显化（因为/所以/虽然/但是…）',     qr/因为|所以|虽然|但是|然而|如果|因此|并且|而且|以及|由于/],
  ['"当…的时候"结构',                     qr/当[^，。！？]{1,14}(?:的时候|时)/],
  ['使役套话（使得/导致/造成/促使）',      qr/使得|导致|造成|促使/],
  ['介词套话（对于/关于/至于/而言）',      qr/对于|关于|至于|而言/],
  ['介词框（在…中/上/下/里）',            qr/在[^，。！？]{1,12}[中上下的里]/],
  ['量词"一个"',                          qr/一个/],
  ['程度副词（非常/十分/相当/极为）',      qr/非常|十分|相当|极为|极其/],
  ['情态动词（应该/必须/可以/能够/将会）', qr/应该|必须|可以|能够|将会|将要/],
  ['"的话"',                              qr/的话/],
  ['"不仅"',                              qr/不仅/],
  ['抽象后缀（性/化/度）',                qr/[\x{4e00}-\x{9fff}](?:性|化|度)/],
);

printf "%-40s %6s %9s\n", '标记', '条数', '占比';
for my $p (@pats) {
    my ($name, $re) = @$p;
    my $c = 0;
    for my $z (@rows) { $c++ if $z =~ $re; }
    printf "%-40s %6d %8.1f%%\n", $name, $c, 100*$c/$n;
}
print "\n";

my ($sum, $long, $vlong, $comma3, $dot2, $de_total, $de2) = (0,0,0,0,0,0,0);
for my $z (@rows) {
    my $len = length $z;
    $sum += $len;
    $long++  if $len > 40;
    $vlong++ if $len > 80;
    my $commas = () = $z =~ /[，、]/g;
    $comma3++ if $commas >= 3;
    my $periods = () = $z =~ /[。！？]/g;
    $dot2++ if $periods >= 2;
    $de_total += () = $z =~ /的/g;
    $de2++ if $z =~ /的[^，。！？]{0,6}的/;
}
printf "平均长度            %6.1f 字\n", $sum/$n;
printf "超过 40 字          %6d %8.1f%%\n", $long, 100*$long/$n;
printf "超过 80 字          %6d %8.1f%%\n", $vlong, 100*$vlong/$n;
printf "≥3 个逗号           %6d %8.1f%%\n", $comma3, 100*$comma3/$n;
printf "≥2 个句末标点       %6d %8.1f%%\n", $dot2, 100*$dot2/$n;
printf "\"的\"密度            %6.1f 个/百字\n", 100*$de_total/$sum;
printf "近距离两个\"的\"      %6d %8.1f%%\n", $de2, 100*$de2/$n;
print "\n";
