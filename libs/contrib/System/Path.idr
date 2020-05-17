module System.Path

import Data.List
import Data.Maybe
import Data.Strings
import Data.String.Extra
import System.Info
import Text.Token
import Text.Lexer
import Text.Parser
import Text.Quantity

private
isWindows : Bool
isWindows = os `elem` ["windows", "mingw32", "cygwin32"]

||| The character that seperates directories in the path
||| on the platform.
export
dirSeperator : Char
dirSeperator = if isWindows then '\\' else '/'

||| The character that seperates multiple paths on the platform.
export
pathSeperator : Char
pathSeperator = if isWindows then ';' else ':'

||| A structure wrapping a Windows' path prefix.
|||
||| @ UNC Windows' Uniform Naming Convention, e.g.,
|||   a network sharing directory: `\\host\c$\Windows\System32`;
||| @ Disk the drive, e.g., "C:". The disk character
|||   is in upper case.
public export
data Volumn = UNC String String
            | Disk Char

||| A single body of a path.
|||
||| @ CurDir represents ".";
||| @ ParentDir represents "..";
||| @ Normal common directory or file.
public export
data Body = CurDir
          | ParentDir
          | Normal String

||| A cross-platform file system path.
|||
||| The function `parse` is most common way to construct a Path,
||| from String, and the function `show` converts the Path to String.
|||
||| Trailing separator is only used for display but is ignored
||| while comparing paths
|||
||| @ volum Windows' path prefix (only on Windows)
||| @ hasRoot whether the path contains a root
||| @ body path bodies
||| @ hasTrailSep whether the path terminates with a separator
public export
record Path where
    constructor MkPath
    volumn : Maybe Volumn
    hasRoot : Bool
    body : List Body
    hasTrailSep : Bool

export
Eq Volumn where
  (==) (UNC l1 l2) (UNC r1 r2) = l1 == r1 && r1 == r2
  (==) (Disk l) (Disk r) = l == r
  (==) _ _ = False

export
Eq Body where
  (==) CurDir CurDir = True
  (==) ParentDir ParentDir = True
  (==) (Normal l) (Normal r) = l == r
  (==) _ _ = False

export
Eq Path where
  (==) (MkPath l1 l2 l3 _) (MkPath r1 r2 r3 _) = l1 == r1 
                                              && l2 == r2 
                                              && l3 == r3

||| Returns a empty path that represents "".
public export
emptyPath : Path
emptyPath = MkPath Nothing False [] False

||| Returns true if the path is absolute.
|||
||| - On Unix, a path is absolute if it starts with the root, 
|||   so isAbsolute and hasRoot are equivalent.
|||
||| - On Windows, a path is absolute if it has a volumn and starts
|||   with the root. e.g., `c:\\windows` is absolute, while `c:temp`
|||   and `\temp` are not, or has UNC volumn prefix.
export
isAbsolute : Path -> Bool
isAbsolute p = if isWindows
                 then case p.volumn of
                           Just (UNC _ _) => True
                           _ => p.hasRoot
                 else p.hasRoot

||| Returns true if the path is relative, i.e., not absolute.
export
isRelative : Path -> Bool
isRelative = not . isAbsolute

||| Appends the right path to the left path.
|||
||| If the path on the right is absolute, it replaces the left path.
|||
||| On Windows:
|||
||| - If path has a root but no volumn (e.g., \windows), it replaces
|||   everything except for the volumn (if any) of self.
||| - If path has a volumn but no root, it replaces self.
export
append : Path -> Path -> Path
append a b = if isAbsolute b || isJust b.volumn
                then b
                else if hasRoot b
                  then record { volumn = a.volumn } b
                  else record { body = a.body ++ b.body,
                                hasTrailSep = b.hasTrailSep } a

||| Returns the path without its final component, if there is one.
|||
||| Returns None if the path terminates in a root or volumn.
export
parent : Path -> Maybe Path
parent p with (p.body)
  parent p | [] = Nothing
  parent p | (x::xs) = Just $ record { body = (init (x::xs)),
                                       hasTrailSep = False } p

||| Returns a list of all parent paths of the path, longest first,
||| without self. 
|||
||| For example, the parent of the path, and the parent of the
||| parent of the path, and so on. The list terminates in a
||| root or volumn.
export
parents : Path -> List Path
parents p = drop 1 $ unfold parent p

||| Determines whether base is one of the parents of the path or is
||| identical to the path.
|||
||| Trailing seperator is ignored.
export
startWith : (base : Path) -> Path -> Bool
startWith b p = b `elem` (unfold parent p)

||| Returns the final body of the path, if there is one.
|||
||| If the path is a normal file, this is the file name. If it's the
||| path of a directory, this is the directory name.
|||
||| Reutrns Nothing if the final body is ".." or ".".
export
fileName : Path -> Maybe String
fileName p = case last' p.body of
                  Just (Normal s) => Just s
                  _ => Nothing

private
splitFileName : String -> (String, String)
splitFileName name 
    = case break (== '.') $ reverse $ unpack name of
           (_, []) => (name, "")
           (_, ['.']) => (name, "")
           (revExt, (dot :: revStem)) 
              => ((pack $ reverse revStem), (pack $ reverse revExt))


||| Extracts the stem (non-extension) portion of the file name of path.
||| 
||| The stem is:
||| 
||| - Nothing, if there is no file name;
||| - The entire file name if there is no embedded ".";
||| - The entire file name if the file name begins with "." and has 
|||   no other "."s within;
||| - Otherwise, the portion of the file name before the final "."
export
fileStem : Path -> Maybe String
fileStem p = pure $ fst $ splitFileName !(fileName p)

||| Extracts the extension of the file name of path.
||| 
||| The extension is:
||| 
||| - Nothing, if there is no file name;
||| - Nothing, if there is no embedded ".";
||| - Nothing, if the file name begins with "." and has no other "."s within;
||| - Otherwise, the portion of the file name after the final "."
export
extension : Path -> Maybe String
extension p = pure $ snd $ splitFileName !(fileName p)

||| Updates the file name of the path.
||| 
||| If no file name, this is equivalent to appending the name.
||| Otherwise it is equivalent to appending the name to the parent.
export
setFileName : (name : String) -> Path -> Path
setFileName name p = record { body $= updateLastBody name } p
  where
    updateLastBody : String -> List Body -> List Body
    updateLastBody s [] = [Normal s] 
    updateLastBody s [Normal _] = [Normal s]
    updateLastBody s [x] = x :: [Normal s]  
    updateLastBody s (x::xs) = x :: (updateLastBody s xs)

||| Updates the extension of the path.
|||
||| Returns Nothing if no file name.
|||
||| If extension is Nothing, the extension is added; otherwise it is replaced.
export
setExtension : (ext : String) -> Path -> Maybe Path
setExtension ext p = do name <- fileName p
                        let (stem, _) = splitFileName name
                        pure $ setFileName (stem ++ "." ++ ext) p

--------------------------------------------------------------------------------
-- Show
--------------------------------------------------------------------------------

export
Show Body where
  show CurDir = "."
  show ParentDir = ".."
  show (Normal s) = s

export
Show Volumn where
  show (UNC server share) = "\\\\" ++ server ++ "\\" ++ share
  show (Disk disk) = singleton disk ++ ":"

||| Display the path in the platform specific format.
export
Show Path where
  show p = let sep = singleton dirSeperator
               volStr = fromMaybe "" (map show p.volumn)
               rootStr = if p.hasRoot then sep else ""
               bodyStr = join sep $ map show p.body
               trailStr = if p.hasTrailSep then sep else "" in
           volStr ++ rootStr ++ bodyStr ++ trailStr

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

private
data PathTokenKind = PTText | PTPunct Char

private
Eq PathTokenKind where
  (==) PTText PTText = True
  (==) (PTPunct c1) (PTPunct c2) = c1 == c2
  (==) _ _ = False

private
PathToken : Type
PathToken = Token PathTokenKind

private
TokenKind PathTokenKind where
  TokType PTText = String
  TokType (PTPunct _) = ()

  tokValue PTText x = x
  tokValue (PTPunct _) _ = ()

private
pathTokenMap : TokenMap PathToken
pathTokenMap = toTokenMap $ 
  [ (is '/', PTPunct '/')
  , (is '\\', PTPunct '\\')
  , (is ':', PTPunct ':')
  , (is '?', PTPunct '?')
  , (some $ non $ oneOf "/\\:?", PTText)
  ]

private
lexPath : String -> Maybe (List PathToken)
lexPath str
    = case lex pathTokenMap str of
           (tokens, _, _, "") => Just $ map TokenData.tok tokens

-- match both '/' and '\\' regardless of the platform.
private
bodySeperator : Grammar PathToken True ()
bodySeperator = (match $ PTPunct '\\') <|> (match $ PTPunct '/')

-- Example: \\?\
-- Windows can automatically translate '/' to '\\'. The verbatim
-- prefix, for example, `\\?\`, disables the transition. Here we
-- simply parse and ignore it.
private
verbatim : Grammar PathToken True ()
verbatim = do count (exactly 2) $ match $ PTPunct '\\'
              match $ PTPunct '?'
              match $ PTPunct '\\'
              pure ()

-- Example: \\server\share
private
unc : Grammar PathToken True Volumn
unc = do count (exactly 2) $ match $ PTPunct '\\'
         server <- match PTText
         bodySeperator
         share <- match PTText
         pure $ UNC server share

-- Example: \\?\server\share
private
verbatimUnc : Grammar PathToken True Volumn
verbatimUnc = do verbatim
                 server <- match PTText
                 bodySeperator
                 share <- match PTText
                 pure $ UNC server share

-- Example: C:
private
disk : Grammar PathToken True Volumn
disk = do text <- match PTText
          disk <- case unpack text of 
                       (disk :: xs) => pure disk 
                       [] => fail "Expect Disk"
          match $ PTPunct ':'
          pure $ Disk (toUpper disk)

-- Example: \\?\C:
private
verbatimDisk : Grammar PathToken True Volumn
verbatimDisk = do verbatim
                  d <- disk
                  pure d

private
parseVolumn : Grammar PathToken True Volumn
parseVolumn = verbatimUnc
          <|> verbatimDisk
          <|> unc
          <|> disk

private
parseBody : Grammar PathToken True Body
parseBody = do text <- match PTText
               pure $ case text of
                           ".." => ParentDir
                           "." => CurDir
                           normal => Normal normal

private
parsePath : Grammar PathToken False Path
parsePath = do vol <- optional parseVolumn
               root <- optional bodySeperator
               body <- sepBy bodySeperator parseBody
               trailSep <- optional bodySeperator
               pure $ MkPath vol (isJust root) body (isJust trailSep)

||| Parse the path from string.
|||
||| The parser is relaxed to accept invalid inputs. Relaxing rules:
|||
||| - Both slash('/') and backslash('\\') are parsed as directory
|||   seperator, regardless of the platform.
||| - Invalid characters in path body, e.g., glob like "/root/*";
||| - Ignoring the verbatim prefix("\\\\?\\") that disables the
|||   automatic translation from slash to backslash (Windows only);
|||
||| ```idris example
||| parse "C:\\Windows/System32"
||| parse "/usr/local/etc/*"
||| ```
export
parse : String -> Maybe Path
parse str = case parse parsePath !(lexPath str) of
                 Right (p, []) => Just p
                 _ => Nothing

||| Parse the parts of the path and appends together.
|||
||| ```idris example
||| parseParts ["/usr", "local/etc"]
||| ```
export
parseParts : (parts : List String) -> Maybe Path
parseParts parts
    = case traverse parse parts of
           Nothing => Nothing
           Just [] => Just emptyPath
           Just (x::xs) => Just $ foldl1 append (x::xs)
