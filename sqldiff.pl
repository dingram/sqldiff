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

  KeyDef : KeyType Identifier(?) KeyAlg(?) '(' KeyList(s /,/) ')' KeyAlg(?)      {$return = {'type'=>$item[1],'name'=>$item[2],'alg'=>$item[3],'fields'=>$item[5],'alg2'=>$item[7]};}
         | KeyTypeFulltextOrSpatial Identifier(?) '(' KeyList(s /,/) ')'   {$return = {'type'=>$item[1],'name'=>$item[2],,'fields'=>$item[4]};}
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

  Type : IntType FieldLength(?) OptFieldOptions       {$return = {'type'=>$item[1],'len'=>$item[2]->[0],'opts'=>$item[3]};}
       | RealType Precision(?) OptFieldOptions        {$return = {'type'=>$item[1],'prec'=>$item[2]->[0],'opts'=>$item[3]};}
       | /float/i FloatOptions(?) OptFieldOptions     {$return = {'type'=>$item[1],'opts'=>$item[3]}; @{$return}{keys %{$item[2]}}=(values %{$item[2]}) if (@{$item[2]});}
       | /bit/i FieldLength(?)                        {$return = {'type'=>$item[1],'len'=>$item[2]->[0]};}
       | /bool(?:ean)?/i                              {$return = {'type'=>$item[1]};}
       | Char FieldLength Binary(?)                   {$return = {'type'=>$item[1],'len'=>$item[2]};}
       | Char Binary(?)                               {$return = {'type'=>$item[1]};}
       | NChar FieldLength BinMod(?)                  {$return = {'type'=>$item[1],'len'=>$item[2],'binary'=>(scalar @{$item[3]})};}
       | NChar BinMod(?)                              {$return = {'type'=>$item[1],'binary'=>(scalar @{$item[3]})};}
       | Varchar FieldLength Binary(?)                {$return = {'type'=>$item[1],'len'=>$item[2]};}
       | NVarchar FieldLength BinMod(?)               {$return = {'type'=>$item[1],'len'=>$item[2],'binary'=>(scalar @{$item[3]})};}
       | /binary/i FieldLength(?)                     {$return = {'type'=>$item[1],'len'=>$item[2]->[0]};}
       | /varbinary/i FieldLength                     {$return = {'type'=>$item[1],'len'=>$item[2]};}
       | /year/i FieldLength(?) OptFieldOptions       {$return = {'type'=>$item[1],'len'=>$item[2]->[0],'opts'=>$item[3]};}
       | /timestamp/i FieldLength(?)                  {$return = {'type'=>$item[1],'len'=>$item[2]->[0]};}
       | /datetime/i                                  {$return = {'type'=>$item[1]};}
       | /date/i                                      {$return = {'type'=>$item[1]};}
       | /time/i                                      {$return = {'type'=>$item[1]};}
       | /tinyblob/i                                  {$return = {'type'=>$item[1]};}
       | /blob/i FieldLength(?)                       {$return = {'type'=>$item[1],'len'=>$item[2]->[0]};}
       | SpatialType                                  {$return = {'type'=>$item[1]};}
       | /mediumblob/i                                {$return = {'type'=>$item[1]};}
       | /longblob/i                                  {$return = {'type'=>$item[1]};}
       | /long varbinary/i                            {$return = {'type'=>$item[1]};}
       | /long/i Varchar Binary(?)                    {$return = {'type'=>$item[1]};}
       | /long/i Binary(?)                            {$return = {'type'=>$item[1]};}
       | /tinytext/i Binary(?)                        {$return = {'type'=>$item[1]};}
       | /text/i FieldLength(?) Binary(?)             {$return = {'type'=>$item[1],'len'=>$item[2]->[0]};}
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

my $parser = new Parse::RecDescent($grammar);
my $sql = join '',(<>);

# preprocess SQL to strip comments and blank lines
$sql =~ s/^\s*--.*$//img;
$sql =~ s{/\*.*?\*/}{}gs;
$sql =~ s/\n+/\n/sg;

#print $sql;

$parser->SqlDump($sql);
