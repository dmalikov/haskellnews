{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | The home page.

module HN.View.Home where

import HN.View
import HN.View.Template

import Data.List.Split

home groups = template "home" mempty $ do
  container $ do
    row $ span12 $ do
      h1 "Haskell News"
      p $ em !. "muted" $ "Updated every 10 minutes."
    forM_ (chunksOf 2 groups) $ \items ->
      row $
        forM_ items $ \(source,items) ->
          span6 $ do
            h2 $ toHtml source
            table !. "table" $
              forM_ items $ \item ->
                tr $ td $ do
                  a ! href (toValue (show (iLink item))) $ toHtml (iTitle item)
                  " — "
                  case iSource item of
                    Hackage -> do
                      preEscapedText (iDescription item)
                    Github ->
                      em $ do toHtml $ iDescription item
                              br
                              toHtml (show (iPublished item))
                    _ -> em $ toHtml (show (iPublished item))
