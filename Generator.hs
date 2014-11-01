module Generator (generateSource) where

import Control.Arrow
import Control.Monad hiding (join)
import Control.Monad.Trans.State hiding (join)
import Data.Char
import Data.Functor
import Data.List
import qualified Data.Map as Map
import Data.Map (Map)
import qualified Data.Set as Set
import Data.Set (Set)
import Data.String.Utils
import Data.Tuple
import Module
import Parser
import Registry
import Text.Printf

data Entry
  = F String
  | E String
  deriving (Eq, Ord, Show)

data Category = C String (Set String)
  deriving (Eq, Ord, Show)

saneEnum :: String -> String
saneEnum = ("GL_"++) . join "_" . tail . split "_"

saneModule :: String -> String
saneModule "422Pixels" = "FourTwoTwoPixels"
saneModule x = x

sanePrefix :: String -> String
sanePrefix "3DFX" = "ThreeDFX"
sanePrefix x = x

commandSignature :: String -> Command -> String
commandSignature monad command =
  join " -> " $
    (parameterSignature $ commandParameters command) ++
    [returnSignature $ commandType command]
  where
    parameterSignature :: [(Type, String)] -> [String]
    parameterSignature params = map (typeSignature . fst) params

    returnSignature :: Type -> String
    returnSignature t = wrap monad True . wrap "Ptr" (typePointer t) $
      case typeName t of
        Nothing -> "()"
        Just "GLvoid" -> "()"
        Just x -> x

    wrap :: String -> Bool -> String -> String
    wrap w True s | any isSpace s = printf "%s (%s)" w s
    wrap w True s = printf "%s %s" w s
    wrap w False s = s

    typeSignature :: Type -> String
    typeSignature t = wrap "Ptr" (typePointer t) $
      case typeName t of
        Nothing -> "()"
        Just "GLvoid" -> "()"
        Just "struct _cl_context" -> "()"
        Just "struct _cl_event" -> "()"
        Just x -> x

ffiCommandName :: String -> String
ffiCommandName
  = ("ffi"++)
  . join ""
  . split "GL"
  . join ""
  . map (filter isAlphaNum)
  . map (replace "()" "V")
  . split " -> "
  . replace "m (" "IO ("
  . replace "m GL" "IO GL"

ffiCommandSignature :: String -> String
ffiCommandSignature cmd = printf "FunPtr (%s) -> %s" x x where 
  x = replace "m (" "IO (" $ replace "m GL" "IO GL" cmd

extensionModuleName :: String -> String
extensionModuleName name =
  printf "Graphics.OpenGL.Extension.%s.%s"
    (sanePrefix prefix) (saneModule $ camelCase (join "_" rest))
  where
    (gl:prefix:rest) = split "_" name

    camelCase :: String -> String
    camelCase str = concat . map (\(x:xs) -> toUpper x : xs) $
      split "_" str

profileModuleName :: String -> String -> (String, Maybe String)
profileModuleName feature profile =
  ( printf "Graphics.OpenGL.Profile.%s" $ fst submodule
  , snd submodule >>= return . printf "Graphics.OpenGL.Profile.%s"
  )
  where
    submodule = case (feature, profile) of
      ("GL_VERSION_1_0", _) -> ("Standard10", Nothing)
      ("GL_VERSION_1_1", _) -> ("Standard11", Nothing)
      ("GL_VERSION_1_2", _) -> ("Standard12", Nothing)
      ("GL_VERSION_1_3", _) -> ("Standard13", Nothing)
      ("GL_VERSION_1_4", _) -> ("Standard14", Nothing)
      ("GL_VERSION_1_5", _) -> ("Standard15", Nothing)
      ("GL_VERSION_2_0", _) -> ("Standard20", Nothing)
      ("GL_VERSION_2_1", _) -> ("Standard21", Nothing)
      ("GL_VERSION_3_0", _) -> ("Standard30", Nothing)
      ("GL_VERSION_3_1", _) -> ("Standard31", Nothing)

      ("GL_VERSION_3_2", "core") -> ("Core32", Just "Compatibility32")
      ("GL_VERSION_3_2", "compatibility") -> ("Compatibility32", Nothing)
      ("GL_VERSION_3_2", _) -> ("Core32", Nothing)

      ("GL_VERSION_3_3", "core") -> ("Core33", Just "Compatibility33")
      ("GL_VERSION_3_3", "compatibility") -> ("Compatibility33", Nothing)
      ("GL_VERSION_3_3", _) -> ("Core33", Nothing)

      ("GL_VERSION_4_0", "core") -> ("Core40", Just "Compatibility40")
      ("GL_VERSION_4_0", "compatibility") -> ("Compatibility40", Nothing)
      ("GL_VERSION_4_0", _) -> ("Core40", Nothing)

      ("GL_VERSION_4_1", "core") -> ("Core41", Just "Compatibility41")
      ("GL_VERSION_4_1", "compatibility") -> ("Compatibility41", Nothing)
      ("GL_VERSION_4_1", _) -> ("Core41", Nothing)

      ("GL_VERSION_4_2", "core") -> ("Core42", Just "Compatibility42")
      ("GL_VERSION_4_2", "compatibility") -> ("Compatibility42", Nothing)
      ("GL_VERSION_4_2", _) -> ("Core42", Nothing)

      ("GL_VERSION_4_3", "core") -> ("Core43", Just "Compatibility43")
      ("GL_VERSION_4_3", "compatibility") -> ("Compatibility43", Nothing)
      ("GL_VERSION_4_3", _) -> ("Core43", Nothing)

      ("GL_VERSION_4_4", "core") -> ("Core44", Just "Compatibility44")
      ("GL_VERSION_4_4", "compatibility") -> ("Compatibility44", Nothing)
      ("GL_VERSION_4_4", _) -> ("Core44", Nothing)

      ("GL_VERSION_4_5", "core") -> ("Core45", Just "Compatibility45")
      ("GL_VERSION_4_5", "compatibility") -> ("Compatibility45", Nothing)
      ("GL_VERSION_4_5", _) -> ("Core45", Nothing)

      ("GL_VERSION_ES_CM_1_0", "common") -> ("EmbeddedCommon10", Nothing)
      ("GL_VERSION_ES_CM_1_0", _) -> ("EmbeddedLite10", Nothing)

      ("GL_ES_VERSION_2_0", _) -> ("Embedded20", Nothing)
      ("GL_ES_VERSION_3_0", _) -> ("Embedded30", Nothing)
      ("GL_ES_VERSION_3_1", _) -> ("Embedded31", Nothing)

      a -> error $ show a

implicitPrelude :: String -> ([String], [Body])
implicitPrelude m = case m of
  "Graphics.OpenGL.Profile.Compatibility32" -> mk [
      "Graphics.OpenGL.Profile.Core32"
    ]
  "Graphics.OpenGL.Profile.Compatibility33" -> mk [
      "Graphics.OpenGL.Profile.Compatibility32"
    , "Graphics.OpenGL.Profile.Core33"
    ]
  "Graphics.OpenGL.Profile.Compatibility40" -> mk [
      "Graphics.OpenGL.Profile.Compatibility32"
    , "Graphics.OpenGL.Profile.Core40"
    ]
  "Graphics.OpenGL.Profile.Compatibility41" -> mk [
      "Graphics.OpenGL.Profile.Compatibility40"
    , "Graphics.OpenGL.Profile.Core41"
    ]
  "Graphics.OpenGL.Profile.Compatibility42" -> mk [
      "Graphics.OpenGL.Profile.Compatibility41"
    , "Graphics.OpenGL.Profile.Core42"
    ]
  "Graphics.OpenGL.Profile.Compatibility43" -> mk [
      "Graphics.OpenGL.Profile.Compatibility42"
    , "Graphics.OpenGL.Profile.Core43"
    ]
  "Graphics.OpenGL.Profile.Compatibility44" -> mk [
      "Graphics.OpenGL.Profile.Compatibility43"
    , "Graphics.OpenGL.Profile.Core44"
    ]
  "Graphics.OpenGL.Profile.Compatibility45" -> mk [
      "Graphics.OpenGL.Profile.Compatibility44"
    , "Graphics.OpenGL.Profile.Core45"
    ]
  "Graphics.OpenGL.Profile.Core33" -> mk [
      "Graphics.OpenGL.Profile.Core32"
    ]
  "Graphics.OpenGL.Profile.Core40" -> mk [
      "Graphics.OpenGL.Profile.Core33"
    ]
  "Graphics.OpenGL.Profile.Core41" -> mk [
      "Graphics.OpenGL.Profile.Core40"
    ]
  "Graphics.OpenGL.Profile.Core42" -> mk [
      "Graphics.OpenGL.Profile.Core41"
    ]
  "Graphics.OpenGL.Profile.Core43" -> mk [
      "Graphics.OpenGL.Profile.Core42"
    ]
  "Graphics.OpenGL.Profile.Core44" -> mk [
      "Graphics.OpenGL.Profile.Core43"
    ]
  "Graphics.OpenGL.Profile.Core45" -> mk [
      "Graphics.OpenGL.Profile.Core44"
    ]
  "Graphics.OpenGL.Profile.EmbeddedCommon10" -> mk [
      "Graphics.OpenGL.Profile.EmbeddedLite10"
    ]
  "Graphics.OpenGL.Profile.Embedded30" -> mk [
      "Graphics.OpenGL.Profile.Embedded20"
    ]
  "Graphics.OpenGL.Profile.Embedded31" -> mk [
      "Graphics.OpenGL.Profile.Embedded30"
    ]
  "Graphics.OpenGL.Profile.Standard11" -> mk [
      "Graphics.OpenGL.Profile.Standard10"
    ]
  "Graphics.OpenGL.Profile.Standard12" -> mk [
      "Graphics.OpenGL.Profile.Standard11"
    ]
  "Graphics.OpenGL.Profile.Standard13" -> mk [
      "Graphics.OpenGL.Profile.Standard12"
    ]
  "Graphics.OpenGL.Profile.Standard14" -> mk [
      "Graphics.OpenGL.Profile.Standard13"
    ]
  "Graphics.OpenGL.Profile.Standard15" -> mk [
      "Graphics.OpenGL.Profile.Standard14"
    ]
  "Graphics.OpenGL.Profile.Standard20" -> mk [
      "Graphics.OpenGL.Profile.Standard15"
    ]
  "Graphics.OpenGL.Profile.Standard21" -> mk [
      "Graphics.OpenGL.Profile.Standard20"
    ]
  "Graphics.OpenGL.Profile.Standard30" -> mk [
      "Graphics.OpenGL.Profile.Standard21"
    ]
  "Graphics.OpenGL.Profile.Standard31" -> mk [
      "Graphics.OpenGL.Profile.Standard30"
    ]
  _ -> ([], [])
  where
    mk names = (map ("module "++) names, [Import names])

requires :: String -> Require -> State (Map Entry Category) ()
requires name req = do
  forM_ (requireEnums req) $ \e -> do
    modify $ Map.adjust (\(C v m) -> C v $ Set.insert name m) (E $ saneEnum e)

  forM_ (requireCommands req) $ \f -> do
    modify $ Map.adjust (\(C v m) -> C v $ Set.insert name m) (F f)

entries :: Registry -> State (Map Entry Category) ()
entries registry = do
  forM_ (registryCommands registry) $ \f -> do
    modify $ Map.insert
      (F $ commandName f)
      (C (commandSignature "m" f) Set.empty)

  forM_ (registryEnums registry) $ \e -> do
    modify $ Map.insert
      (E . saneEnum $ enumName e)
      (C (enumValue e) Set.empty)

  forM_ (registryExtensions registry) $ \ext -> do
    forM_ (extensionRequires ext) $ \req -> do
      requires (extensionModuleName $ extensionName ext) req

  forM_ (registryFeatures registry) $ \fe -> do
    let feature = featureName fe

    forM_ (featureRequires fe) $ \req -> do
      let name = fst . profileModuleName feature $ requireProfile req
      requires name req

      when (startswith "Graphics.OpenGL.Profile.Standard" name) $
        requires "Graphics.OpenGL.Profile.Core32" req

    forM_ (featureRemoves fe) $ \rm -> do
      let profile = removeProfile rm
      let (name, removeName) = profileModuleName feature profile

      forM_ (removeEnums rm) $ \e -> do
        modify $ Map.adjust
          (\(C v m) -> C v $ Set.delete name m)
          (E $ saneEnum e)

        case removeName of
          Just name' -> modify $ Map.adjust
            (\(C v m) -> C v $ Set.insert name' m) (E $ saneEnum e)
          Nothing -> return ()

      forM_ (removeCommands rm) $ \f -> do
        modify $ Map.adjust
          (\(C v m) -> C v $ Set.delete name m)
          (F f)

        case removeName of
          Just name' -> modify $ Map.adjust
            (\(C v m) -> C v $ Set.insert name' m) (F f)
          Nothing -> return ()

modules :: Registry
        -> Map Entry Category
        -> State (Map String [(Bool, Entry, String)]) ()
modules registry entr = do
  forM_ (registryExtensions registry) $ \ext -> do
    modify $ Map.insert (extensionModuleName $ extensionName ext) []

  forM_ profiles $ \profile -> do
    modify $ Map.insert (printf "Graphics.OpenGL.Profile.%s" profile) []

  forM_ (Map.toList entr) $ \(k, C v ms) -> do
    forM_ (Set.toList ms) $ \m -> do
      modify $ Map.alter (f (Set.size ms > 1, k, v)) m
  where
    f r Nothing = Just [r]
    f r (Just a) = Just $ a ++ [r]

    profiles = [
        "Compatibility32"
      , "Compatibility33"
      , "Compatibility40"
      , "Compatibility41"
      , "Compatibility42"
      , "Compatibility43"
      , "Compatibility44"
      , "Compatibility45"
      , "Core32"
      , "Core33"
      , "Core40"
      , "Core41"
      , "Core42"
      , "Core43"
      , "Core44"
      , "Core45"
      , "EmbeddedCommon11"
      , "EmbeddedLite11"
      , "Embedded20"
      , "Embedded30"
      , "Embedded31"
      , "Standard10"
      , "Standard11"
      , "Standard12"
      , "Standard13"
      , "Standard14"
      , "Standard15"
      , "Standard20"
      , "Standard21"
      , "Standard30"
      , "Standard31"
      ]

data FunMap = FunMap
  { funSignatures :: Map String String -- signature by method name
  , funExtensions :: Map String String -- module name to extension name
  } deriving (Eq, Show)

funMap :: Registry -> [(Bool, Entry, String)] -> FunMap
funMap registry entries = FunMap
  (Map.fromList [ n | (_, F n, _) <- entries ])
  (Map.fromList $ map ((extensionModuleName&&&id).extensionName) $ registryExtensions registry)

funMapSignature :: String -> FunMap -> String
funMapSignature i (FunMap m _) = Map.findWithDefault undefined i m

funMapFst :: FunMap -> Map Int String
funMapFst (FunMap m _ _ _) = m

funExtInfoByModule :: String -> FunMap -> Maybe String
funExtInfoByModule s = Map.lookup s . funExtensions

funBody :: FunMap -> String -> String -> [Body]
funBody fm n v =
  [ Function n ("MonadIO m => " ++ v) $ strip body
  , Function np ("FunPtr(" ++ v'  ++ ")") (getExtension
  , Code $ printf "{-# NOINLINE " ++ np ++ "#-}" np
  ] where
  np = n ++ FunPtr
  numArgs = subtract 2 . length $ split " -> " v
  params = join " " $ map (\x -> "v" ++ show x) [0..numArgs]
  v' = replace "m (" "IO (" $ replace "m GL" "IO GL" v
  body = printf "= %s %sFunPtr" ( ) n
    (funMapByFunction n fm)
    params

mkFFI :: FunMap -> Module
mkFFI fm = Module "Graphics.GL.Raw.FFI" export body where
  export = [ Section "Invokers" (nub $ ffiCommandName <$> Map.keys fm) ]
  body = 
    [ Import
      [ "Foreign.C.String"
      , "Foreign.C.Types"
      , "Foreign.Marshal.Alloc"
      , "Foreign.Ptr"
      , "Foreign.Storable"
      , "Graphics.OpenGL.Types"
      , "Unsafe.Coerce"
      ]
    ] ++ nub (
      map (\(n, f) -> Code $ printf "foreign import ccall \"dynamic\"\n\t%s :: %s"
            (ffiCommandName $ funMapSignature n fm)
            (ffiCommandSignature $ funMapSignature n fm)
          ) (Map.toList $ funMapSignatures fm)
    )
    -- TODO: m variants

mkShared :: FunMap -> [(Bool, Entry, String)] -> Module
mkShared fm entr = Module "Graphics.OpenGL.Internal.Shared" [] body
  where
    imp =
      [ Import
        [ "Graphics.OpenGL.Internal.Scope"
        , "Graphics.OpenGL.Basic"
        ]
      ]

    body = imp ++ (concat . map bodyF $ nub entr)
    bodyF (False, _, _) = []
    bodyF (_, E n, v) = [Pattern n "GLenum" ("= " ++ v)]
    bodyF (_, F n, v) = [funBody fm n v]

mkModule :: FunMap -> String -> [(Bool, Entry, String)] -> Module
mkModule fm m entr = Module m export body
  where
    entryName (E n) = "pattern " ++ n
    entryName (F n) = n

    (ie, ib) = implicitPrelude m
    hasShared = not . null $ filter (\(s, _, _) -> s) entr
    shared = case hasShared of
      True -> [Import
        [ "Graphics.OpenGL.Internal.Shared"
        ]]
      False -> []

    export = case funExtInfoByModule m fm of
      Just (i, en) ->
        [ Section "Extension Support" $
          [ "gl_" ++ (join "_" . tail $ split "_" en)
          ]
        , Section en $ ie ++ map (\(s, e, _) -> entryName e) entr
        ]
      Nothing ->
        [ Section m $ ie ++ map (\(s, e, _) -> entryName e) entr
        ]

    body =
      [ Import
        [ "Graphics.OpenGL.Internal.Scope"
        , "Graphics.OpenGL.Basic"
        ]
      ] ++
      shared ++ ib ++ extCheck ++ concatMap bodyF entr

    extCheck = case funExtInfoByModule m fm of
      Just (i, en) ->
        [ Function
          ("gl_" ++ (join "_" . tail $ split "_" en))
          "(Monad m, MonadReader e m, HasScope e) => m Bool"
          ("= extGL " ++ show i)
        ]
      Nothing -> []

    bodyF (True, _, _) = []
    bodyF (_, E n, v) = [Pattern n "GLenum" ("= " ++ v)]
    bodyF (_, F n, v) = [funBody fm n v]

mkExtensionGather :: FunMap -> [Module]
mkExtensionGather fm = (flip map) extensionGroups $
  \x -> Module (printf "Graphics.OpenGL.Extension.%s" $ sanePrefix x)
    [Section (printf "%s Extensions" x) $ map ("module "++) $ extInGroup x]
    [Import $ extInGroup x]
  where
  extInGroup grp
    = map fst
    . sort
    . filter (\x -> grp == (head . tail . split "_" . snd $ snd x))
    . Map.toList $ funExt fm

  extensionGroups
    = sort
    . nub
    . map (head . tail . split "_" . snd . snd)
    . Map.toList $ funExt fm

mkExtensionGroupGather :: [Module] -> Module
mkExtensionGroupGather ms = Module "Graphics.OpenGL.Extension"
  [Section "Extensions" $ map (("module "++) . moduleName) ms]
  [Import $ map moduleName ms]

generateSource :: Registry -> IO ()
generateSource registry = do
  let s = execState (entries registry) Map.empty
  let m = execState (modules registry s) Map.empty
  let fm' = concatMap snd $ Map.toList m
  let fm = funMap registry fm'
  saveModule $ mkShared fm fm'
  saveModule $ mkFFI fm
  mapM_ (saveModule . uncurry (mkModule fm)) $ Map.toList m
  let exts = mkExtensionGather fm
  mapM_ saveModule $ exts
  saveModule $ mkExtensionGroupGather exts