Import-Module Pester

BeforeAll {
  . ($PSCommandPath.Replace('.Tests', ''))

  function PreAndPostProcessCli {
    param (
      [Parameter(Mandatory, ValueFromPipeline)] [String] $code
    )
    $code | PreProcessCppCli | PostProcessCppCli
  }
}

Describe 'C++/CLI Formatting' {

  # Test separately: only testing the sequence of Pre-Post results in the same code
  # could still mean it simply does nothing at all.
  Context 'PreProcessCppCli' {
    It 'Does nothing without instructions' {
      @'
Foo^ Func(Bar^ arg, FooBar^ arg);
'@ | PreProcessCppCli | Should -Be @'
Foo^ Func(Bar^ arg, FooBar^ arg);
'@
    }

    It 'Replaces carets for specific types' {
      @'
//cli-type Foo
//cli-type Bar
//cli-type List< int >
//cli-type Tuple< String^, String^ >
Foo^ Func(Bar^ arg, FooBar^ arg, Bar* arg);
List< int > ^  Func( Bar ^  arg, Bar^arg);
Tuple<String ^, String^>^ Func();
'@ | PreProcessCppCli | Should -Be @'
//cli-type Foo
//cli-type Bar
//cli-type List< int >
//cli-type Tuple< String^, String^ >
FooMARK* Func(BarMARK* arg, FooBar^ arg, Bar* arg);
ListMARK< int >*  Func( BarMARK*  arg, BarMARK*arg);
TupleMARK< String^, String^ >* Func();
'@
    }

    It 'Replaces brackets for specific indexers' {
      @'
//cli-indexer Foo
//cli-indexer Bar
property type Foo[int];
property type Bar [ int ];
'@ | PreProcessCppCli | Should -Be @'
//cli-indexer Foo
//cli-indexer Bar
property type Foo( intMARK );
property type Bar( intMARK );
'@
    }

    It 'Applies inverse of postprocessing fixes with ForceClangFormatStyle' {
      @'
#using <Foo>
Foo^ Bar(Foo% x)
bool::typeid

public ref class Stuff

public ref struct Stuff

public enum class Stuff

[Serializable] public ref class Data

template< class T >
public ref class Data
'@ | PreProcessCppCli -ForceClangFormatStyle | Should -Be @'
#using < Foo>
Foo ^ Bar(Foo % x)
bool ::typeid

public

ref class Stuff

public

ref struct Stuff

public

enum class Stuff

[Serializable] public ref class Data

template< class T >
public ref class Data
'@
    }
  }

  Context 'PreAndPostProcessCli' {
    It 'Restores replacements' {
      @'
//cli-type Foo
//cli-type List< int >
//cli-indexer Bar
//cli-type Tuple< String^, String^ >
Foo^ Func(Foo* arg);
List< int >^ Bar[int]
Tuple<String ^,  String^>^ Func();
'@ | PreAndPostProcessCli | Should -Be @'
//cli-type Foo
//cli-type List< int >
//cli-indexer Bar
//cli-type Tuple< String^, String^ >
Foo^ Func(Foo* arg);
List< int >^ Bar[ int ]
Tuple< String^, String^ >^ Func();
'@
    }
  }

  Context 'PostProcessCppCli' {
    It 'Fixes newlines in class definitions' {
      @'
public

ref class Foo;

public

ref Struct Foo;

public
enum class Foo;
'@ | PostProcessCppCli | Should -Be @'
public ref class Foo;

public ref struct Foo;

public enum class Foo;
'@
    }

    It 'Fixes #using whitespace' {
      @'
#using <  Foo>
'@ | PostProcessCppCli | Should -Be @'
#using <Foo>
'@
    }

    It 'Fixes pointer-like whitespace' {
      @'
Foo ^
template<Foo> ^
Bar  %
'@ | PostProcessCppCli | Should -Be @'
Foo^
template<Foo>^
Bar%
'@
    }

    It 'Fixes leading typeid whitespace' {
      @'
bool ::typeid
Bar ::typeid
'@ | PostProcessCppCli | Should -Be @'
bool::typeid
Bar::typeid
'@
    }
  }
}
