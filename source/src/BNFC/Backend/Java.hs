{-
    BNF Converter: Java Top File
    Copyright (C) 2004  Author:  Markus Forsberg, Peter Gammie,
                                 Michael Pellauer, Bjorn Bringert

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

-------------------------------------------------------------------
-- |
-- Module      :  JavaTop
-- Copyright   :  (C)opyright 2003, {markus, aarne, pellauer, peteg, bringert} at cs dot chalmers dot se
-- License     :  GPL (see COPYING for details)
--
-- Maintainer  :  {markus, aarne} at cs dot chalmers dot se
-- Stability   :  alpha
-- Portability :  Haskell98
--
-- Top-level for the Java back end.
--
-- > $Id: JavaTop15.hs,v 1.12 2007/01/08 18:20:23 aarne Exp $
-------------------------------------------------------------------

module BNFC.Backend.Java ( makeJava ) where

-------------------------------------------------------------------
-- Dependencies.
-------------------------------------------------------------------
import System.FilePath (pathSeparator)
import BNFC.Utils
import Data.List ( intercalate)
import BNFC.CF
import BNFC.Options as Options
import BNFC.Backend.Base
import BNFC.Backend.Java.CFtoCup15 ( cf2Cup )
import BNFC.Backend.Java.CFtoJLex15
import BNFC.Backend.Java.CFtoAntlr4Lexer
import BNFC.Backend.Java.CFtoAntlr4Parser
import BNFC.Backend.Java.CFtoJavaAbs15 ( cf2JavaAbs )
import BNFC.Backend.Java.CFtoJavaPrinter15
import BNFC.Backend.Java.CFtoVisitSkel15
import BNFC.Backend.Java.CFtoComposVisitor
import BNFC.Backend.Java.CFtoAbstractVisitor
import BNFC.Backend.Java.CFtoFoldVisitor
import BNFC.Backend.Java.CFtoAllVisitor
import BNFC.Backend.Common.NamedVariables (SymEnv)
import qualified BNFC.Backend.Common.Makefile as Makefile
import BNFC.PrettyPrint
-------------------------------------------------------------------
-- | Build the Java output.
-- FIXME: get everything to put the files in the right places.
-- Adapt Makefile to do the business.
-------------------------------------------------------------------

type TestClass = String -> String -> CF -> String

parserLexerSelector :: String -> JavaLexerParser -> ParserLexerSpecification
parserLexerSelector _ JLexCup = mkParserLexerSpecification cf2JLex cf2cup javaTest --- FIXME cup file needs not be called as
parserLexerSelector _ JFlexCup = mkParserLexerSpecification cf2JFlex cf2cup javaTest
parserLexerSelector l Antlr4 = mkParserLexerSpecification (cf2AntlrLex' l) (cf2AntlrParse' l) antlrTest

data ParserLexerSpecification = ParseLexSpec{
    parser :: CFToParser  ,
    lexer  :: CFToLexer   ,
    testclass :: TestClass
}

-- positional constructor
mkParserLexerSpecification :: CFToLexer -> CFToParser -> TestClass -> ParserLexerSpecification
mkParserLexerSpecification tl tp tc = ParseLexSpec {
    parser = tp,
    lexer = tl,
    testclass = tc
}

--- CF -> LEXER GENERATION TOOL BRIDGE
-- | type of function translating the CF to an appropriate lexer generation tool.
type CF2LexerFunction = String -> CF -> (Doc, SymEnv)
-- Chooses the translation from CF to the lexer
data CFToLexer = CF2Lex {
    cf2lex :: String -> CF -> (Doc, SymEnv),
    makelexerdetails :: MakeFileDetails
}
-- | Shorthand for positional constructor
mkCFtoLexer :: CF2LexerFunction -> MakeFileDetails -> CFToLexer
mkCFtoLexer fu mf = CF2Lex {
    cf2lex = fu,
    makelexerdetails = mf
}

-- | Instances of cf-lexergen bridges
cf2JLex, cf2JFlex:: CFToLexer
cf2JLex     = mkCFtoLexer BNFC.Backend.Java.CFtoJLex15.cf2jlex' jlexmakedetails
cf2JFlex    = mkCFtoLexer BNFC.Backend.Java.CFtoJLex15.cf2jflex' jflexmakedetails
cf2AntlrLex' :: String -> CFToLexer
cf2AntlrLex' l = mkCFtoLexer BNFC.Backend.Java.CFtoAntlr4Lexer.cf2AntlrLex $ antlrmakedetails $ l++"Lexer" -- TODO


--- CF -> PARSER GENERATION TOOL BRIDGE
-- | type of function translating the CF to an appropriate parser generation tool.
type CF2ParserFunction = String -> String -> CF -> SymEnv -> String
-- Chooses the translation from CF to the parser
data CFToParser = CF2Parse {
    cf2parse :: CF2ParserFunction,
    makeparserdetails :: MakeFileDetails
}
-- |  Shorthand for positional constructor
mkCFtoParser :: CF2ParserFunction -> MakeFileDetails -> CFToParser
mkCFtoParser fu mf = CF2Parse {
    cf2parse = fu,
    makeparserdetails = mf
}
-- | Instances of cf-parsergen bridges
cf2cup :: CFToParser
cf2cup = mkCFtoParser BNFC.Backend.Java.CFtoCup15.cf2Cup cupmakedetails
cf2AntlrParse' :: String -> CFToParser
cf2AntlrParse' l = mkCFtoParser BNFC.Backend.Java.CFtoAntlr4Parser.cf2AntlrParse $ antlrmakedetails $ l++"Parser"


-- | shorthand for Makefile command running javac or java
runJavac , runJava:: String -> String
runJava s = mkRunProgram "JAVA" s
runJavac s = mkRunProgram "JAVAC" s

-- | function returning a string executing a program contained in a variable j on input s
-- mkRunProgram "JAVA" "apackage.Main"
-- >>> ${JAVA} ${JAVA_FLAGS} apackage.Main
mkRunProgram :: String -> String -> String
mkRunProgram j s = (Makefile.refVar j) +++ (Makefile.refVar (j +-+ "FLAGS")) +++ s


type OutputDirectory = String

--- MAKEFILE DETAILS FROM RUNNING THE PARSER-LEXER GENERATION TOOLS
-- | executable : the string that executes the generation tool
-- | flags : a string containing flags to pass to the tool
-- | filename : the input file to the tool
-- | toolname : name of the tool
-- | toolversion : tool version
-- | supportsEntryPoints : true if the tool is a parser and supports entry points, false otherwise
-- | results : list of names (without extension!) of files resulting
--             from the application of the tool which are relevant to
--             a make rule
data MakeFileDetails = MakeDetails {
    executable::String,
    flags::(OutputDirectory -> String),
    filename::String,
    fileextension::String,
    toolname::String,
    toolversion::String,
    supportsEntryPoints::Bool,
    results :: [String],
    moveresults :: Bool
}

-- Positional constructor.
mkMakeFileDetails :: String -> (OutputDirectory->String) -> String -> String -> String -> String -> Bool -> [String] -> Bool -> MakeFileDetails
mkMakeFileDetails x f fil ex tn tv sup res mr = MakeDetails{
    executable = x,
    flags = f,
    filename = fil,
    fileextension = ex,
    toolname = tn,
    toolversion = tv,
    supportsEntryPoints = sup,
    results = res,
    moveresults = mr
}

mapEmpty :: a->String
mapEmpty = (\_ -> "")

-- Instances of makefile details.
cupmakedetails, jflexmakedetails, jlexmakedetails :: MakeFileDetails
jlexmakedetails  = mkMakeFileDetails (runJava "JLex.Main") mapEmpty "Yylex" "" "JLex" "1.2.6." False ["Yylex"] False
jflexmakedetails = mkMakeFileDetails "jflex" mapEmpty "Yylex" "" "JFlex" "?" False ["Yylex"] False
cupmakedetails = mkMakeFileDetails (runJava "java_cup.Main") (\_ -> "-nopositions -expect 100") "_cup" "cup" "CUP" "0.10k" False ["parser", "sym"] True
antlrmakedetails :: String -> MakeFileDetails
antlrmakedetails l = mkMakeFileDetails
    (runJava "org.antlr.v4.Tool")
    (\x -> intercalate " " $ map (+++(take ((length x) - 1 ) x )) [ "-lib", "-package"])
    l "g4" "ANTLRv4" "4.5" True [l] False -- TODO

prependPath , appendExtension :: String -> [String] -> [String]
prependPath s fi = [s ++ x | x<- fi]
appendExtension s fi = [x+.+s | x<- fi]


dotJava,dotClass :: [String] -> [String]
dotJava a = appendExtension "java" a
dotClass a = appendExtension "class" a


type CFToJava = String -> String -> CF -> String

data BNFCGeneratedEntities = BNFCGenerated {
    bprettyprinter :: (String, String),
    btest :: (String, String),
    bcompos :: (String, String),
    babstract :: (String, String),
    bfold :: (String,  String),
    ball :: (String,  String),
    bskel :: (String,  String)
}

bnfcVisitorsAndTests :: String -> String -> CF ->
                            CFToJava ->  CFToJava -> CFToJava -> CFToJava -> CFToJava -> CFToJava -> CFToJava -> BNFCGeneratedEntities
bnfcVisitorsAndTests pbase pabsyn cf cf0 cf1 cf2 cf3 cf4 cf5 cf6 =
 BNFCGenerated{
    bprettyprinter = ( "PrettyPrinter" , app cf0),
    bskel = ( "VisitSkel", app cf1),
    bcompos = ( "ComposVisitor" , app cf2),
    babstract = ( "AbstractVisitor" , app cf3),
    bfold = ( "FoldVisitor", app cf4),
    ball = ( "AllVisitor", app cf5),
    btest = ( "Test" , app cf6)
 }
    where app x = x pbase pabsyn cf

-- This creates files to be mentioned in the makefile.
-- It is fine to have it relatively untouched and divide anyway antlr in two grammar: parser grammar and lexer grammar
makeJava :: SharedOptions -> CF -> MkFiles ()
makeJava options@Options{..} cf =
    do -- Create the package directories if necessary.
       let packageBase = case inPackage of
                             Nothing -> lang
                             Just p -> p ++ "." ++ lang
           packageAbsyn = packageBase ++ "." ++ "Absyn"
           dirBase = pkgToDir packageBase
           dirAbsyn = pkgToDir packageAbsyn
           javaex str = dirBase ++ str +.+ "java"
           bnfcfiles = bnfcVisitorsAndTests packageBase packageAbsyn cf
                            cf2JavaPrinter
                            cf2VisitSkel
                            cf2ComposVisitor
                            cf2AbstractVisitor
                            cf2FoldVisitor
                            cf2AllVisitor
                            (testclass parselexspec)
           makebnfcfile x = mkfile (javaex (fst $ x bnfcfiles)) $ (snd $ x bnfcfiles)

       let absynFiles = remDups $ cf2JavaAbs packageBase packageAbsyn cf
           absynBaseNames = map fst absynFiles
           absynFileNames = map (dirAbsyn ++) absynBaseNames
       let writeAbsyn (filename, contents) =
               mkfile (dirAbsyn ++ filename ++ ".java") contents
       mapM_ writeAbsyn absynFiles
       makebnfcfile bprettyprinter
       makebnfcfile bskel
       makebnfcfile bcompos
       makebnfcfile babstract
       makebnfcfile bfold
       makebnfcfile ball
       makebnfcfile btest
---       mkfile ("Test" ++ name) $ "java " ++ dirBase ++ "Test $(1)"
       let (lex, env) = lexfun packageBase cf
       -- where the lexer file is created. lex is the content!
       mkfile (dirBase ++ (inputfile lexmake) ) lex
       liftIO $ putStrLn $ "   (Tested with "+++ (toolname lexmake ) +++ (toolversion lexmake ) +++")"
       -- where the parser file is created.
       mkfile (dirBase ++ (inputfile parmake))
            $ parsefun packageBase packageAbsyn cf env
       liftIO $ putStrLn $ case (supportsEntryPoints parmake) of
                            False -> "   (Parser created only for category " ++ show (firstEntry cf) ++ ")" -- JLex- JFlex specific (in antlr you have a parser for each category)
                            _ -> ""
       liftIO $ putStrLn $ "   (Tested with " +++ (toolname parmake) +++ (toolversion parmake ) +++ ")"
       Makefile.mkMakefile options $ makefile lang dirBase dirAbsyn absynFileNames parselexspec
    where
      remDups [] = []
      remDups ((a,b):as) = case lookup a as of
                             Just {} -> remDups as
                             Nothing -> (a, b) : remDups as

      pkgToDir :: String -> FilePath
      pkgToDir s = replace '.' pathSeparator s ++ [pathSeparator]
      parselexspec = parserLexerSelector lang javaLexerParser
      lexfun = cf2lex $ lexer parselexspec
      parsefun = cf2parse $ parser parselexspec
      parmake = makeparserdetails (parser parselexspec)
      lexmake = makelexerdetails (lexer parselexspec)



-- FIXME It's almost certainly better to just feed all the Java source
-- files to javac in one go.
-- Replace with an ANT script?
-- This writes the rules/declares variables for running the lexer/parser.
-- FIXME Must automate the creation of makefile rules based on input-outputs to the generation tools.
-- It needs not to separate brutally the makefile creation.
makefile :: String -> FilePath -> FilePath -> [String] -> ParserLexerSpecification -> Doc
makefile name dirBase dirAbsyn absynFileNames jlexpar = vcat $
    makeVars [  ("JAVAC", "javac"),
                ("JAVAC_FLAGS", "-sourcepath ."),
                ( "JAVA", "java"),
                ( "JAVA_FLAGS", ""),
            -- parser executable
                ( "PARSER", (executable parmake)),
            -- parser flags
                ( "PARSER_FLAGS", (flags parmake) dirBase),
             -- lexer executable (and flags?)
                ( "LEXER", (executable lexmake)),
                ( "LEXER_FLAGS", (flags lexmake) dirBase)
    ]
    ++
    makeRules [ ("all", [ "test" ], []),
                ( "test", ("absyn" : classes), []),
                ( ".PHONY", ["absyn"],     []),
                ("%.class", [ "%.java" ],  [ runJavac "$^" ]),
                ("absyn",   [absynJavaSrc],[ runJavac "$^" ])
                ]++
    [
  -- running the lexergen: output of lexer -> input of lexer : calls lexer
    let ff = filename lexmake -- name of input file without extension
        dirBaseff = dirBase ++ ff -- prepend directory
        inp = dirBase ++ (inputfile lexmake) in
        Makefile.mkRule (dirBaseff +.+ "java") [ inp ]
        [ "${LEXER} ${LEXER_FLAGS} "++ inp ]

    -- running the parsergen, these there are its outputs
    -- output of parser -> input of parser : calls parser
  , let ff = filename parmake
        dirBaseff = dirBase ++ ff
        inp = dirBase ++ (inputfile parmake) in
        Makefile.mkRule (intercalate " " (map (dirBase++) $ (dotJava $ results parmake)))
          [ inp ] $
          [ "${PARSER} ${PARSER_FLAGS} " ++ inp
          ]++ if moveresults parmake then ["mv " ++ (unwords $ dotJava $ results parmake)+++ dirBase ] else []

  -- Class of the output of lexer generator wants java of : output of lexer and parser generator
  ,
    let lexerOutClass = dirBase ++ (filename lexmake) +.+ "class"
        outname = \x -> dirBase ++ x +.+ "java"
        deps = map outname ((results lexmake) ++ (results parmake)) in
    Makefile.mkRule (lexerOutClass) deps []
  ]++
  -- Class of output of parser generator wants java of output of parser generator.
  -- Changing this to the
  --, Makefile.mkRule (dirBase ++ "sym.class") [ dirBase ++ "sym.java" ] []
  --, Makefile.mkRule (dirBase ++ "parser.class") [ dirBase ++ "parser.java", dirBase ++ "sym.java" ] []
  (reverse [Makefile.mkRule tar dep [] | (tar,dep) <- partialParserGoals dirBase (results parmake)])
  -- This remains the same, it's the prettyprinting of BNFC
  ++[ Makefile.mkRule (dirBase ++ "PrettyPrinter.class") [ dirBase ++ "PrettyPrinter.java" ] []

  -- Removes all the class files created anywhere
  , Makefile.mkRule "clean" [] [ "rm -f " ++ dirAbsyn ++ "*.class" ++ " " ++ dirBase ++ "*.class" ]

  -- Remains the same
  , Makefile.mkRule "distclean" [ "vclean" ] []

  -- removes everything
  , Makefile.mkRule "vclean" [] [ " rm -f " ++ absynJavaSrc ++ " " ++ absynJavaClass
                                  , " rm -f " ++ dirAbsyn ++ "*.class"
                                  --     , "rm -f " ++ "Test" ++ name
                                  , " rmdir " ++ dirAbsyn
                                  , " rm -f " ++ unwords (map (dirBase ++) $
                                              [inputfile lexmake,
                                              inputfile parmake]++
                                              dotJava (results lexmake)++
                                              ["VisitSkel.java",
                                              "ComposVisitor.java",
                                              "AbstractVisitor.java",
                                              "FoldVisitor.java",
                                              "AllVisitor.java",
                                              "PrettyPrinter.java",
                                              "Skeleton.java",
                                              "Test.java"]++
                                              (dotJava (results parmake))++
                                              ["*.class"])
                                  , " rm -f Makefile"
                                  , " rmdir -p " ++ dirBase ]
    ]
    where
      makeVars x = [Makefile.mkVar n v | (n,v) <- x]
      makeRules x = [Makefile.mkRule tar dep recipe  | (tar, dep, recipe) <- x]
      parmake           = makeparserdetails (parser jlexpar)
      lexmake           = makelexerdetails (lexer jlexpar)
      absynJavaSrc      = unwords (dotJava absynFileNames)
      absynJavaClass    = unwords (dotClass absynFileNames)
      classes = prependPath dirBase lst
      lst = (dotClass (results lexmake)) ++ [ "PrettyPrinter.class", "Test.class"
          , "ComposVisitor.class", "AbstractVisitor.class"
          , "FoldVisitor.class", "AllVisitor.class"]++
           (dotClass (results parmake)) ++ ["Test.class"]


bnfcGenerated = [ "PrettyPrinter", "Test", "ComposVisitor", "AbstractVisitor", "FoldVisitor", "AllVisitor"]

inputfile x = (filename x) ++ case fileextension x of
                                        "" -> ""
                                        a -> "."++a

partialParserGoals :: String -> [String] -> [(String, [String])]
partialParserGoals _ [] = []
partialParserGoals dbas (x:rest) = ((dbas++x+.+"class"),(map (\y ->dbas++y+.+"java") (x:rest))):(partialParserGoals dbas rest)




antlrTest :: String -> String -> CF -> String
antlrTest packageBase packageAbsyn cf = render $ vcat
    [
        "package" <+> text packageBase <> ";"
        ,"import org.antlr.v4.gui.TestRig;"
        ,"public class Test"
        ,codeblock 2
          [ "public static void main(String args[]) throws Exception"
            ,codeblock 2 [
            "TestRig tr = new TestRig(args);"
            ,"tr.process();"
            ]
          ]
    ]

-- This needs not be here with antlr, you can use TestRig.
javaTest :: String -> String -> CF -> String
javaTest packageBase packageAbsyn cf = render $ vcat
    [ "package" <+> text packageBase <> ";"
    , "import java_cup.runtime.*;"
    , "import" <+> text packageBase <> ".*;"
    , "import" <+> text packageAbsyn <> ".*;"
    , "import java.io.*;"
    , ""
    , "public class Test"
    , codeblock 2
        [ "public static void main(String args[]) throws Exception"
        , codeblock 2
            [ "Yylex l = null;"
            , "parser p;"
            , "try"
            , codeblock 2
                [ "if (args.length == 0) l = new Yylex(new InputStreamReader(System.in));"
                , "else l = new Yylex(new FileReader(args[0]));" ]
            , "catch(FileNotFoundException e)"
            , "{"
            , " System.err.println(\"Error: File not found: \" + args[0]);"
            , " System.exit(1);"
            , "}"
            , "p = new parser(l);"
            , "/* The default parser is the first-defined entry point. */"
            , "/* You may want to change this. Other options are: */"
            , "/* " <> fsep (punctuate "," (showOpts (tail eps))) <> " */"
            , "try"
            , "{"
            , "  " <> text packageAbsyn <> "." <> text (show def) <+> "parse_tree = p.p"
             <> text (show def) <> "();"
            , "  System.out.println();"
            , "  System.out.println(\"Parse Succesful!\");"
            , "  System.out.println();"
            , "  System.out.println(\"[Abstract Syntax]\");"
            , "  System.out.println();"
            , "  System.out.println(PrettyPrinter.show(parse_tree));"
            , "  System.out.println();"
            , "  System.out.println(\"[Linearized Tree]\");"
            , "  System.out.println();"
            , "  System.out.println(PrettyPrinter.print(parse_tree));"
            , "}"
            , "catch(Throwable e)"
            , "{"
            , "  System.err.println(\"At line \" + String.valueOf(l.line_num()) + \", near \\\"\" + l.buff() + \"\\\" :\");"
            , "  System.err.println(\"     \" + e.getMessage());"
            , "  System.exit(1);"
            , "}"
            ]
        ]
    ]
  where
    eps = allEntryPoints cf
    def = head eps
    showOpts [] = []
    showOpts (x:xs) | normCat x /= x = showOpts xs
                    | otherwise      = text ('p' : identCat x) : showOpts xs
