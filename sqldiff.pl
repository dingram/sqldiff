#!/usr/bin/perl
use strict;
use warnings;
use DBI;

use Parse::RecDescent;
use Data::Dumper;

my $grammar = q{
  SqlDump : SqlStatement(s) eofile
          | <error>

  SqlStatement : Statement(?) Semicolon
               | <error>

  Statement : UseStatement
            | CreateDatabaseStatement
            | CreateTableStatement
            | DropTableStatement
            | <error>

  UseStatement : /use/i Identifier { print STDERR "Select database: $item[2]\n"; }

  CreateDatabaseStatement : /create/i /database/i Identifier { print STDERR "Database: $item[3]\n"; }




  CreateTableStatement : {$::curtbl={};} /create/i /table/i IfNotExists(?) <commit> Identifier {$::curtbl->{'name'}=$item[-1]; print STDERR "Parsing table $::curtbl->{name}...";} '(' <leftop: FieldListItem /\s*,\s*/ FieldListItem> ')' {$::curtbl->{'fields'} = $item[-2];} CreateTableOptions(?)
                          {$::curtbl->{'options'}=$item[-1]->[0]; $::tables->{$::curtbl->{'name'}} = $::curtbl; print STDERR " ok\n";}

  CreateTableOptions : <leftop: CreateTableOption /\s*(?:,\s*)?/ CreateTableOption>    { $return={}; @{$return}{keys %$_}=(values %$_) foreach (@{$item[1]}); }

  CreateTableOption : /engine/i          OptEqual StorageEngines  {$return = {lc $item[1], $item[3]};}
                    | /auto_increment/i  OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /type/i            OptEqual StorageEngines  {$return = {lc $item[1], $item[3]};}
                    | /max_rows/i        OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /min_rows/i        OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /avg_row_length/i  OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /comment/i         OptEqual String          {$return = {lc $item[1], $item[3]};}
                    | /pack_keys/i       OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /pack_keys/i       OptEqual /default/i      {$return = {lc $item[1], $item[3]};}
                    | /checksum/i        OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /delay_key_write/i OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /row_format/i      OptEqual RowTypes        {$return = {lc $item[1], $item[3]};}
                    | /raid_type/i       OptEqual RaidTypes       {$return = {lc $item[1], $item[3]};}
                    | /raid_chunks/i     OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | /raid_chunksize/i  OptEqual UInt            {$return = {lc $item[1], $item[3]};}
                    | DefaultCharset
                    | DefaultCollation
                    | <error>

  DefaultCharset : Default(?) Charset OptEqual Ident        {$return = {lc $item[2], $item[4]};}

  DefaultCollation : Default(?) /collate/i OptEqual Ident   {$return = {lc $item[2], $item[4]};}

  Default : /DEFAULT/i

  FieldListItem : ColumnDef
                | KeyDef
                | <error>

  ColumnDef : FieldSpec

  KeyDef : KeyType Identifier(?) KeyAlg(?) '(' KeyList(s /,/) ')' KeyAlg(?)      {$return = {'constraint'=>[],'type'=>$item[1],'name'=>$item[2],'alg'=>$item[3],'fields'=>$item[5],'alg2'=>$item[7]};}
         | KeyTypeFulltextOrSpatial Identifier(?) '(' KeyList(s /,/) ')'   {$return = {'constraint'=>[],'type'=>$item[1],'name'=>$item[2],'fields'=>$item[4]};}
         | Constraint(?) ConstraintKeyType Identifier(?) KeyAlg(?) '(' KeyList(s /,/) ')' KeyAlg(?)   {$return = {'constraint'=>$item[1],'type'=>$item[2],'name'=>$item[3],'alg'=>$item[4],'fields'=>$item[6],'alg2'=>$item[8]};}
         | Constraint   {$return = {'constraint'=>$item[1]};}

  KeyAlg : /using/i BtreeRtree(?)  {$return=$item[2]->[0];}
         | /type/i BtreeRtree(?)   {$return=$item[2]->[0];}

  KeyType : KeyOrIndex

  KeyOrIndex : /key/i
             | /index/i

  BtreeRtree : /btree/i
             | /rtree/i
             | /hash/i

  ConstraintKeyType : /primary/i /key/i         {$return = $item[1];}
                    | /unique/i KeyOrIndex(?)   {$return = $item[1];}

  KeyList : KeyPart OrderDir   { $return={'order'=>$item[2]}; @{$return}{keys %{$item[1]}}=(values %{$item[1]}); }

  KeyPart : Identifier '(' UNum ')'   {$return={'name'=>$item[1],'length'=>$item[3]};}
          | Identifier                {$return={'name'=>$item[1]};}

  KeyTypeFulltextOrSpatial : /fulltext/i KeyOrIndex(?)
                           | /spatial/i KeyOrIndex(?)

  OrderDir : /asc/i
           | /desc/i
           | {$return = 'asc';}

  Constraint : /constraint/i Identifier(?)

  FieldSpec : FieldIdent Type OptAttributes   { $return = {'name'=>$item[1],'type'=>$item[2],'attrs'=>$item[3]}; }

  OptAttributes: Attribute(s?)    { $return={}; @{$return}{keys %$_}=(values %$_) foreach (@{$item[1]}); }

  Type : IntType FieldLength(?) OptFieldOptions       {$return = {'type'=>$item[1],'length'=>$item[2]->[0],'opts'=>$item[3]};}
       | RealType Precision(?) OptFieldOptions        {$return = {'type'=>$item[1],'prec'=>$item[2]->[0],'opts'=>$item[3]};}
       | /float/i FloatOptions(?) OptFieldOptions     {$return = {'type'=>$item[1],'opts'=>$item[3]}; @{$return}{keys %{$item[2]}}=(values %{$item[2]}) if (@{$item[2]});}
       | /bit/i FieldLength(?)                        {$return = {'type'=>$item[1],'length'=>$item[2]->[0]};}
       | /bool(?:ean)?/i                              {$return = {'type'=>$item[1]};}
       | Char FieldLength Binary(?)                   {$return = {'type'=>$item[1],'length'=>$item[2]};}
       | Char Binary(?)                               {$return = {'type'=>$item[1]};}
       | NChar FieldLength BinMod(?)                  {$return = {'type'=>$item[1],'length'=>$item[2],'binary'=>(scalar @{$item[3]})};}
       | NChar BinMod(?)                              {$return = {'type'=>$item[1],'binary'=>(scalar @{$item[3]})};}
       | Varchar FieldLength Binary(?)                {$return = {'type'=>$item[1],'length'=>$item[2]};}
       | NVarchar FieldLength BinMod(?)               {$return = {'type'=>$item[1],'length'=>$item[2],'binary'=>(scalar @{$item[3]})};}
       | /binary/i FieldLength(?)                     {$return = {'type'=>$item[1],'length'=>$item[2]->[0]};}
       | /varbinary/i FieldLength                     {$return = {'type'=>$item[1],'length'=>$item[2]};}
       | /year/i FieldLength(?) OptFieldOptions       {$return = {'type'=>$item[1],'length'=>$item[2]->[0],'opts'=>$item[3]};}
       | /timestamp/i FieldLength(?)                  {$return = {'type'=>$item[1],'length'=>$item[2]->[0]};}
       | /datetime/i                                  {$return = {'type'=>$item[1]};}
       | /date/i                                      {$return = {'type'=>$item[1]};}
       | /time/i                                      {$return = {'type'=>$item[1]};}
       | /tinyblob/i                                  {$return = {'type'=>$item[1]};}
       | /blob/i FieldLength(?)                       {$return = {'type'=>$item[1],'length'=>$item[2]->[0]};}
       | SpatialType                                  {$return = {'type'=>$item[1]};}
       | /mediumblob/i                                {$return = {'type'=>$item[1]};}
       | /longblob/i                                  {$return = {'type'=>$item[1]};}
       | /long varbinary/i                            {$return = {'type'=>$item[1]};}
       | /long/i Varchar Binary(?)                    {$return = {'type'=>$item[1]};}
       | /long/i Binary(?)                            {$return = {'type'=>$item[1]};}
       | /tinytext/i Binary(?)                        {$return = {'type'=>$item[1]};}
       | /text/i FieldLength(?) Binary(?)             {$return = {'type'=>$item[1],'length'=>$item[2]->[0]};}
       | /mediumtext/i Binary(?)                      {$return = {'type'=>$item[1]};}
       | /longtext/i Binary(?)                        {$return = {'type'=>$item[1]};}
       | /decimal/i FloatOptions(?) OptFieldOptions   {$return = {'type'=>$item[1],'opts'=>$item[3]}; @{$return}{keys %{$item[2]}}=(values %{$item[2]}) if (@{$item[2]});}
       | /numeric/i FloatOptions(?) OptFieldOptions   {$return = {'type'=>$item[1],'opts'=>$item[3]}; @{$return}{keys %{$item[2]}}=(values %{$item[2]}) if (@{$item[2]});}
       | /fixed/i FloatOptions(?) OptFieldOptions     {$return = {'type'=>$item[1],'opts'=>$item[3]}; @{$return}{keys %{$item[2]}}=(values %{$item[2]}) if (@{$item[2]});}
       | /enum/i '(' StringList ')' Binary(?)         {$return = {'type'=>$item[1],'values'=>$item[3]};}
       | /set/i '(' StringList ')' Binary(?)          {$return = {'type'=>$item[1],'values'=>$item[3]};}
       | /serial/i                                    {$return = {'type'=>$item[1]};}

  OptFieldOptions : FieldOption(s?)  {$return={}; @{$return}{keys %$_}=(values %$_) foreach (@{$item[1]});}

  SpatialType : /geometry/i
              | /geometrycollection/i
              | /point/i
              | /multipoint/i
              | /line/i
              | /multiline/i
              | /polygon/i
              | /multipolygon/i

  Char : /char/i

  NChar : /nchar/i
        | /national/i Char

  Varchar : Char /varying/i
          | /varchar/i

  NVarchar : /national varchar/i
           | /nvarchar/i
           | /nchar varchar/i
           | /national char varying/i
           | /nchar varying/i

  IntType : /int/i
          | /tinyint/i
          | /smallint/i
          | /mediumint/i
          | /bigint/i

  RealType : /real/i
           | /double/i
           | /double precision/i

  FloatOptions : FieldLength    {$return={'length'=>$item[-1]};}
               | Precision      {$return={'precision'=>$item[-1]};}

  Precision : '(' Int ',' Int ')'   {$return=[@item[2,4]];}

  FieldOption : /signed/i     {$return={'signed'=>1};}
              | /unsigned/i   {$return={'signed'=>0};}
              | /zerofill/i   {$return={'zerofill'=>1};}

  FieldLength : '(' UNum ')' {$return=$item[2];}

  Attribute : /null/i                               {$return={'null'=>1};}
            | /not null/i                           {$return={'null'=>0};}
            | /default/i NowOrSignedLiteral         {$return={'default'=>$item[-1]};}
            | /on/i /update/i /current_timestamp/i  {$return={'on_update'=>'current_timestamp'};}
            | /auto_increment/i                     {$return={'auto_increment'=>1};}
            | Primary(?) /key/i                     {$return={'keytype'=>(scalar @{$item[1]}?'primary':'key')};}
            | /unique key/i                         {$return={'keytype'=>'unique'};}
            | /unique/i                             {$return={'keytype'=>'unique'};}
            | /comment/i String                     {$return={'comment'=>$item[-1]};}
            | /collate/i Collation                  {$return={'collate'=>$item[-1]};}

  Primary : /primary/i

  NowOrSignedLiteral : /current_timestamp/i
                     | SignedLiteral

  Binary : /ascii/i BinMod(?)              {$return={'charset'=>$item[1].((scalar @{$item[2]})?' '.$item[2]->[0]:'')};}
         | /byte/i
         | /unicode/i BinMod(?)
         | Charset CharsetName BinMod(?)
         | /binary/i BinCharset(?)

  BinCharset : /ascii/i
             | /unicode/i
             | Charset CharsetName

  Charset : /charset/i
          | /character/i /set/i
          | /char/i /set/i

  CharsetName : /binary/i
              | IdentOrText

  BinMod : /binary/i

  StorageEngines : IdentOrText

  RowTypes : /default/i
           | /fixed/i
           | /dynamic/i
           | /compressed/i
           | /redundant/i
           | /compact/i

  RaidTypes : /striped/i
            | /raid0/i
            | UInt

  Collation : IdentOrText

  IdentOrText : Ident
              | String

  SignedLiteral : Literal
                | '+' UNum   {$return='+'.$item[2];}
                | '-' UNum   {$return='-'.$item[2];}

  Literal : TextLiteral
          | UNum
          | /null/i
          | /false/i
          | /true/i
          | HexNum
          | BinNum
          | UnderscoreCharset HexNum
          | UnderscoreCharset BinNum
          | /date/i TextLiteral        {$return=join ' ',@item[1,2];}
          | /time/i TextLiteral        {$return=join ' ',@item[1,2];}
          | /timestamp/i TextLiteral   {$return=join ' ',@item[1,2];}

  TextLiteral : String

  UnderscoreCharset :

  HexNum : /X'[0-9a-f]+'/i
         | /0x[0-9a-fA-F]+/
  BinNum : /b'[01]+'/i
         | /0b[01]+/



  DropTableStatement : /drop table/i IfExists(?) Identifier   #{ if (defined $::tables->{$item[3]}) { unset $::tables->{$item[3]}; print "Dropped table $item[3]"; } }

  IfExists : /if exists/i

  IfNotExists : /if not exists/i

  OptEqual : '='
           |

  FieldIdent : Identifier
             | Identifier '.' Identifier   { $return = $item[1].'.'.$item[3]; }
             | '.' Identifier              { $return = $item[2]; }

  Identifier : /(?:primary|using)/i <commit> <reject>
             | Ident
             | IdentQuoted

  IdentQuoted : '`' Ident '`'   { $return = $item[2]; }

  Ident : /[a-z_]\w*/i

  StringList : <leftop: String ',' String>
  String : <perl_quotelike> { $return = $item[-1][2]; }

  Int  : /(?:0|-?[1-9][0-9]*)/
  UInt : /(?:0|[1-9][0-9]*)/

  Num  : /(?:0|-?[1-9][0-9]*)(?:\.[0-9]+)?/
  UNum : /(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/

  Semicolon : ';'
            | <error>

  eofile  : /^\Z/
};

$Parse::RecDescent::skip='[ \t\r\n]*';
$::RD_HINT    =1;
$::RD_WARN    =1;


##############################################################################
#                                                                            #
#                                 Main program                               #
#                                                                            #
##############################################################################

unless (scalar @ARGV == 2) {
  print STDERR "Usage: sqldiff source.sql target.sql\n";
  exit 1;
}

my $file_a = $ARGV[0];
my $file_b = $ARGV[1];
my $fh;

print "-- \n-- SQL diff generated at ".(scalar localtime)."\n-- \n\n";

open $fh, '<', $file_a or die "Could not open first file: $!\n";
my $sql_a = join '',(<$fh>);
close $fh;

open $fh, '<', $file_b or die "Could not open second file: $!\n";
my $sql_b = join '',(<$fh>);
close $fh;

print STDERR "Constructing parser... ";
my $parser = new Parse::RecDescent($grammar);
print STDERR "ok\n";

print STDERR "Parsing first database...\n";
my $db_a = parseSQL($sql_a);
print STDERR "Finished parsing first database...\n";

print STDERR "Parsing second database...\n";
my $db_b = parseSQL($sql_b);
print STDERR "Finished parsing second database...\n";

#print Dumper($db_a);
#print Dumper($db_b);

my $diff = findDiffs($db_a, $db_b);

print STDERR "\n\n";

outputDiff($diff);

outputDiffSQL($diff);

print "-- \n-- End of SQL diff (at ".(scalar localtime).")\n-- \n\n";



##############################################################################
#                                                                            #
#                               End main program                             #
#                                                                            #
##############################################################################

sub parseSQL {
  my ($sql) = @_;

  # preprocess SQL to strip comments and blank lines
  $sql =~ s/^\s*--.*$//img;
  $sql =~ s{/\*.*?\*/}{}gs;
  $sql =~ s/\n+/\n/sg;

  $::tables = {};
  $parser->SqlDump($sql);

  my $ret = $::tables;
  $::tables = {};

  # post-process tables to separate constraints
  foreach my $k (keys %$ret) {
    my (%fields, @constraints);
    foreach my $f (@{$ret->{$k}{fields}}) {
      if (exists $f->{constraint}) {
        push @constraints, $f;
      } else {
        $fields{$f->{name}} = $f;
      }
    }
    $ret->{$k}{fields} = {%fields};
    $ret->{$k}{constraints} = [@constraints];
  }

  return $ret;
}

sub outputDiff {
  my ($diff) = @_;

  foreach my $type (qw(tables columns indexes)) {
    print "\n\e[1;33mType: ", ucfirst $type, "\e[m\n";
    foreach my $action (qw(add mod del)) {
      next unless @{$diff->{$type}{$action}};
      my $char = $action eq 'add' ? "\e[1;32m+" : $action eq 'mod' ? "\e[1;36m~" : "\e[1;31m-";
      foreach my $item (@{$diff->{$type}{$action}}) {
        print "$char ", $item->{name}, " with ", (scalar keys %{$item->{fields}}), " field(s)\e[m\n";
      }
    }
  }
  print "\n\e[1;35mEnd of diff summary\e[m\n";
}

sub createTableSQL {
  my ($tbl) = @_;
  my $sql = '';
  my $i=0;

  $sql .= "CREATE TABLE `". $tbl->{name}. "` (";
  # fields
  $i=0;
  foreach my $field (values %{$tbl->{fields}}) {
    $sql .= ', ' if ($i++);
    $sql .= "`".$field->{name}."` ";
  }
  # constraints
  $sql .= ") ";
  # options
  $sql .= ";\n";

  return $sql;
}

sub outputDiffSQL {
  my ($diff) = @_;

  print "\n";
  foreach my $tbl (@{$diff->{tables}{add}}) {
    print createTableSQL($tbl);
  }
  print "\n";
  foreach my $tbl (@{$diff->{tables}{del}}) {
    print 'DROP TABLE `', $tbl->{name}, "`;\n";
  }
  print "\n";
}

sub findDiffs {
  my ($db_a, $db_b) = @_;
  my $diff = {
    'tables'=>{
      'add'=>[],
      'mod'=>[],
      'del'=>[]
    },
    'columns'=>{
      'add'=>[],
      'mod'=>[],
      'del'=>[]
    },
    'indexes'=>{
      'add'=>[],
      'mod'=>[],
      'del'=>[]
    },
  };

  foreach (keys %$db_b) {
    if (!defined $db_a->{$_}) {
      # new table
      push @{$diff->{tables}{add}}, $db_b->{$_};
      next;
    }
    # table exists in both; check columns
    my $tbl_a = $db_a->{$_};
    my $tbl_b = $db_b->{$_};
  }

  foreach (keys %$db_a) {
    if (!defined $db_b->{$_}) {
      # new table
      push @{$diff->{tables}{del}}, $db_a->{$_};
      next;
    }
  }

  return $diff;
}
