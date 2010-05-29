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

  Statement : UseStatement { print "\033[1;32mUSE\033[m"; }
            | CreateDatabaseStatement { print "\033[1;32mCREATE DB\033[m"; }
            | CreateTableStatement { print "\033[1;32mCREATE TABLE\033[m"; }
            | DropTableStatement { print "\033[1;32mDROP TABLE\033[m"; }
            | InsertStatement { print "\033[1;32mINSERT\033[m"; }
            | <error>

  UseStatement : /use/i Identifier

  CreateDatabaseStatement : /create/i /database/i Identifier




  CreateTableStatement : /create/i /table/i <skip:'[ \t\r\n]*'> IfNotExists(?) Identifier Create2

  Create2 : '(' <leftop: FieldListItem Comma FieldListItem> <skip:'[ \t\r\n]*'> ')' CreateTableOptions(?)
          | <error>

  Comma : /\s*,\s*/

  CreateTableOptions : CreateTableOption ',' CreateTableOptions
                     | CreateTableOption CreateTableOptions
                     | CreateTableOption

  CreateTableOption : /engine/i OptEqual StorageEngines
                    | /auto_increment/i OptEqual UInt
                    | /type/i OptEqual StorageEngines
                    | /max_rows/i OptEqual UInt
                    | /min_rows/i OptEqual UInt
                    | /avg_row_length/i OptEqual UInt
                    | /comment/i OptEqual String
                    | /pack_keys/i OptEqual UInt
                    | /pack_keys/i OptEqual /default/i
                    | /checksum/i OptEqual UInt
                    | /delay_key_write/i OptEqual UInt
                    | /row_format/i OptEqual RowTypes
                    | /raid_type/i OptEqual RaidTypes
                    | /raid_chunks/i OptEqual UInt
                    | /raid_chunksize/i OptEqual UInt
                    | DefaultCharset
                    | DefaultCollation
                    | <error>

  DefaultCharset : Default(?) Charset OptEqual Ident

  DefaultCollation : Default(?) /collate/i OptEqual Ident

  Default : /DEFAULT/i

  FieldListItem : ColumnDef
                | KeyDef
                | <error>

  ColumnDef : FieldSpec

  KeyDef : KeyType Identifier(?) KeyAlg '(' KeyList(s /,/) ')' KeyAlg
         | KeyTypeFulltextOrSpatial Identifier(?) '(' KeyList(s /,/) ')'
         | Constraint(?) ConstraintKeyType Identifier(?) KeyAlg '(' KeyList(s /,/) ')' KeyAlg
         | Constraint

  KeyAlg : /using/i BtreeRtree(?)
         | /type/i BtreeRtree(?)
         |

  KeyType : KeyOrIndex

  KeyOrIndex : /key/i
             | /index/i

  BtreeRtree : /btree/i
             | /rtree/i
             | /hash/i

  ConstraintKeyType : /primary/i /key/i
                    | /unique/i KeyOrIndex(?)

  KeyList : KeyPart OrderDir

  KeyPart : Identifier '(' UNum ')'
          | Identifier

  KeyTypeFulltextOrSpatial : /fulltext/i KeyOrIndex(?)
                           | /spatial/i KeyOrIndex(?)

  OrderDir : /asc/i
           | /desc/i
           |

  Constraint : /constraint/i Identifier(?)

  FieldSpec : FieldIdent Type OptAttributes

  OptAttributes: Attribute(s?)

  Type : IntType FieldLength(?) FieldOption(s?)
       | RealType Precision(?) FieldOption(s?)
       | /float/i FloatOptions(?) FieldOption(s?)
       | /bit/i
       | /bit/i FieldLength
       | /bool(?:ean)?/i
       | Char FieldLength Binary(?)
       | Char Binary(?)
       | NChar FieldLength BinMod(?)
       | NChar BinMod(?)
       | /binary/i FieldLength
       | /binary/i
       | Varchar FieldLength Binary(?)
       | NVarchar FieldLength BinMod(?)
       | /varbinary/i FieldLength
       | /year/i FieldLength(?) FieldOption(s?)
       | /timestamp/i FieldLength(?)
       | /datetime/i
       | /date/i
       | /time/i
       | /tinyblob/i
       | /blob/i FieldLength(?)
       | SpatialType
       | /mediumblob/i
       | /longblob/i
       | /long varbinary/i
       | /long/i Varchar Binary(?)
       | /tinytext/i Binary(?)
       | /text/i FieldLength(?) Binary(?)
       | /mediumtext/i Binary(?)
       | /longtext/i Binary(?)
       | /decimal/i FloatOptions(?) FieldOption(s?)
       | /numeric/i FloatOptions(?) FieldOption(s?)
       | /fixed/i FloatOptions(?) FieldOption(s?)
       | /enum/i '(' StringList ')' Binary(?)
       | /set/i '(' StringList ')' Binary(?)
       | /long/i Binary(?)
       | /serial/i

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

  FloatOptions : FieldLength
               | Precision

  Precision : '(' Int ',' Int ')'

  FieldOption : /signed/i
              | /unsigned/i
              | /zerofill/i

  FieldLength : '(' UNum ')'

  Attribute : /null/i
            | /not null/i
            | /default/i NowOrSignedLiteral
            | /on update current_timestamp/i
            | /auto_increment/i
            | Primary(?) /key/i
            | /unique key/i
            | /unique/i
            | /comment/i String
            | /collate/i Collation

  Primary : /primary/i

  NowOrSignedLiteral : /current_timestamp/i
                     | SignedLiteral

  Binary : /ascii/i BinMod(?)
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
                | '+' UNum
                | '-' UNum

  Literal : TextLiteral
          | UNum
          | /null/i
          | /false/i
          | /true/i
          | HexNum
          | BinNum
          | UnderscoreCharset HexNum
          | UnderscoreCharset BinNum
          | /date/i TextLiteral
          | /time/i TextLiteral
          | /timestamp/i TextLiteral

  TextLiteral : String

  UnderscoreCharset :

  HexNum : /X'[0-9a-f]+'/i
         | /0x[0-9a-fA-F]+/
  BinNum : /b'[01]+'/i
         | /0b[01]+/



  DropTableStatement : /drop table/i IfExists(?) Identifier

  InsertStatement : /insert (?:into)?/ Identifier

  IfExists : /if exists/i

  IfNotExists : /if not exists/i

  OptEqual : '='
           |

  FieldIdent : Identifier
             | Identifier '.' Identifier
             | '.' Identifier

  Identifier : /(?:primary|using)/i <commit> <reject>
             | Ident
             | IdentQuoted

  IdentQuoted : '`' Ident '`'

  Ident : /[a-z_]\w*/i

  StringList : <leftop: String ',' String>
  String : <perl_quotelike>

  Int  : /(?:0|-?[1-9][0-9]*)/
  UInt : /(?:0|[1-9][0-9]*)/

  Num  : /(?:0|-?[1-9][0-9]*)(?:\.[0-9]+)?/
  UNum : /(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/

  Semicolon : {print "\033[1;31m;\033[m\n";} ';'
            | <error>

  eofile  : /^\Z/
};

#$Parse::RecDescent::skip='';
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
