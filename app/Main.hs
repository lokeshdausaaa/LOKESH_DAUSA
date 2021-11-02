module Main where

import Cli (Cli (Cli, pastesDir, repopulateDb), opts)
import Control.Exception (SomeException)
import Data.Aeson (encode)
import Data.Proxy (Proxy (..))
import Data.Text as T (Text, unpack)
import Database (getRandomName, migrate, populateFromFile, repopulateFromFs)
import Database.SQLite.Simple (open)
import Network.HTTP.Types.Status (status500)
import Network.Wai (Request, Response, responseLBS)
import Network.Wai.Handler.Warp
  ( Settings,
    defaultSettings,
    runSettings,
    setOnException,
    setOnExceptionResponse,
    setPort,
  )
import Options.Applicative
import Routes (create, fetch, root)
import Servant (Proxy (..), serve, type (:<|>) ((:<|>)))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import Types (BatbinAPI, Status (Status))
import Wrappers (cRouteWrapper, fRouteWrapper, rootRouteWrapper)

-- wai-wide exception handler
erSettings :: Int -> Settings
erSettings port = setOnExceptionResponse errHandler $ setPort port defaultSettings

errHandler :: SomeException -> Response
errHandler se = do
  responseLBS status500 [] (encode $ Status False "Something went wrong!")

-- wai-wide exception logger
ebSettings :: Maybe Request -> SomeException -> IO ()
ebSettings _ se = do
  putStrLn "\n---------- [ERR] Exception thrown with message:"
  print se

batbinServer :: Cli -> IO ()
batbinServer cli = do
  let port = 8080 :: Int
  let db = "batbin.db"

  didExist <- doesFileExist db
  pdExist <- createDirectoryIfMissing True (pastesDir cli)
  conn <- open db

  migrate conn

  if not didExist then populateFromFile conn "words_alpha.txt" else pure ()
  if repopulateDb cli then repopulateFromFs conn (pastesDir cli) else pure ()

  let app =
        serve
          (Proxy :: Proxy BatbinAPI)
          ( rootRouteWrapper root
              :<|> fRouteWrapper fetch conn
              :<|> cRouteWrapper create conn
          )

  putStrLn $ "[i] starting paste server on port " <> show port
  runSettings (setOnException ebSettings $ erSettings port) app

batbin :: Cli -> IO ()
batbin (Cli pastesDir repopulateDb) = undefined

main :: IO ()
main = batbin =<< execParser opts'
  where
    opts' =
      info
        opts
        ( fullDesc
            <> progDesc "Run a paste server or use as a client to interact with a paste server"
            <> header "Batbin Server+Client"
        )
