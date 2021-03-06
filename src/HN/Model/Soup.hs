{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- | Download and import from HTML soup because the services were too
-- stingy to provide an RSS feed.

module HN.Model.Soup where

import HN.Data
import HN.Monads
import HN.Model
import HN.Model.Items
import HN.Types
import HN.Curl

import Control.Applicative
import Control.Monad.Error
import Data.Time
import Network.URI
import Snap.App
import System.Locale
import Text.HTML.TagSoup
import Text.HTML.TagSoup.Match
import TagSoup

--------------------------------------------------------------------------------
-- Google+

importGooglePlus :: Model c s (Either String ())
importGooglePlus = do
  result <- io $ downloadString "https://plus.google.com/communities/104818126031270146189"
  case result of
    Left e -> return (Left (show e))
    Right html ->
      case runSoup (parseTags html) getShares of
        Left e -> return (Left e)
        Right items -> do mapM_ (addItem GooglePlus) items
                          return (Right ())

-- | Get Google+ shares.
getShares :: Soup [NewItem]
getShares = do
  skipTagByName "header"
  skipTagByName "a"
  author <- nextText
  a <- gotoTagByName "a"
  link <- fmap ("https://plus.google.com/" ++) (getAttrib "href" a)
  uri <- meither "couldn't parse URI" (parseURI link)
  tstr <- nextText
  time <- parseDate tstr
  skipTagByName "span"
  skipTagByName "div"
  skipTagByName "div"
  skipTagByName "div"
  desc <- get >>= return . tagsText . takeWhile (not . tagOpen (const True) (any (isInfixOf "+1") . map snd))
  items <- getShares <|> return []
  return $ NewItem
    { niTitle = trim author ++ " shares: " ++ trim (unwords (take 10 (words desc)) ++ " ...")
    , niDescription = desc
    , niLink = uri
    , niPublished = time
    } : items

--------------------------------------------------------------------------------
-- Github

-- | Import a list of repos from Github's “latest created Haskell repos” list.
importGithub :: Model c s (Either String ())
importGithub = do
  result <- io $ downloadString "https://github.com/languages/Haskell/created"
  case result of
    Left e -> return (Left (show e))
    Right str ->
      case runSoup (parseTags str) extractItems of
        Left e -> return (Left e)
        Right items -> do mapM_ (addItem Github) items
                          return (Right ())

-- | Skip to the repo list and extract the items.
extractItems :: Soup [NewItem]
extractItems = do
  skipTagByNameAttrs "ul" (any (\(key,value) -> key == "class" && isPrefixOf "repolist" value))
  collectItems

-- | Collect items into a loop. This loops.
collectItems :: Soup [NewItem]
collectItems = do
  skipTagByName "h3"
  a <- gotoTagByName "a"
  name <- nextText
  link <- fmap ("http://github.com" ++) (getAttrib "href" a)
  uri <- meither "couldn't parse URI" (parseURI link)
  skipTagByNameAttrs "div" (any (\(key,value) -> key == "class" && "body" == value))
  state <- get
  modify $ takeWhile (not . tagClose (=="div"))
  desc <- (do skipTagByNameAttrs "p" (any (\(key,value) -> key == "class" && "description" == value))
              nextText)
          <|> return ""
  put state
  timetag <- gotoTagByName "time"
  time <- getAttrib "datetime" timetag
  t <- parseGithubTime time
  items <- collectItems <|> return []
  return $ NewItem
    { niTitle = trim name
    , niDescription = trim desc
    , niLink = uri
    , niPublished = t
    } : items

--------------------------------------------------------------------------------
-- Twitter

-- | Import recent Tweets from the search.
importTwitter :: Model c s (Either String ())
importTwitter = do
  result <- io $ downloadString "https://twitter.com/search?q=haskell%20-rugby%20-jewelry%20%23haskell&src=typd"
  case result of
    Left e -> return (Left (show e))
    Right str ->
      case runSoup (parseTags str) extractTwitterItems of
        Left e -> return (Left e)
        Right items -> do mapM_ (addItem Twitter) items
                          return (Right ())

-- | Skip to each tweet and extract the items.
extractTwitterItems :: Soup [NewItem]
extractTwitterItems = go where
  go = do
    skipTagByNameClass "li" "stream-item"
    skipTagByNameClass "div" "original-tweet"
    skipTagByNameClass "div" "content"
    skipTagByNameClass "span" "username"
    skipTagByName "b"
    username <- nextText
    a <- gotoTagByNameClass "a" "tweet-timestamp"
    link <- getAttrib "href" a
    uri <- meither "couldn't parse URI" (parseURI ("https://twitter.com" ++ link))
    timestamp <- gotoTagByName "span"
    epoch <- getAttrib "data-time" timestamp
    published <- parseEpoch epoch
    gotoTagByNameClass "p" "tweet-text"
    tags <- get
    let tweet = tagsTxt (takeWhile (not . tagCloseLit "p") tags)
    items <- go <|> return []
    return $ NewItem
      { niTitle = username ++ ": " ++ tweet
      , niPublished = published
      , niDescription = ""
      , niLink = uri
      } : items
