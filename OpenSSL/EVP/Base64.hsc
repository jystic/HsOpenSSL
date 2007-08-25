{- -*- haskell -*- -}

-- |An interface to Base64 codec.

module OpenSSL.EVP.Base64
    ( -- * Encoding
      encodeBase64
    , encodeBase64BS
    , encodeBase64LBS

      -- * Decoding
    , decodeBase64
    , decodeBase64BS
    , decodeBase64LBS
    )
    where

import           Control.Exception
import           Data.ByteString.Base
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy.Char8 as L8
import           Data.List
import           Foreign
import           Foreign.C


-- エンコード時: 最低 3 バイト以上になるまで次のブロックを取り出し續け
-- る。返された[ByteString] は B8.concat してから、その文字列長より小さ
-- な最大の 3 の倍數の位置で分割し、殘りは次のブロックの一部と見做す。
--
-- デコード時: 分割のアルゴリズムは同じだが最低バイト数が 4。
nextBlock :: Int -> ([ByteString], LazyByteString) -> ([ByteString], LazyByteString)
nextBlock _      (xs, LPS [] ) = (xs, LPS [])
nextBlock minLen (xs, LPS src) = if foldl' (+) 0 (map B8.length xs) >= minLen then
                                     (xs, LPS src)
                                 else
                                     case src of
                                       (y:ys) -> nextBlock minLen (xs ++ [y], LPS ys)


{- encode -------------------------------------------------------------------- -}

foreign import ccall unsafe "EVP_EncodeBlock"
        _EncodeBlock :: Ptr CChar -> Ptr CChar -> Int -> IO Int


encodeBlock :: ByteString -> ByteString
encodeBlock inBS
    = unsafePerformIO $
      unsafeUseAsCStringLen inBS $ \ (inBuf, inLen) ->
      createAndTrim maxOutLen $ \ outBuf ->
      _EncodeBlock (castPtr outBuf) inBuf inLen
    where
      maxOutLen = (inputLen `div` 3 + 1) * 4 + 1 -- +1: '\0'
      inputLen  = B8.length inBS


-- |@'encodeBase64' str@ lazilly encodes a stream of data to
-- Base64. The string doesn't have to be finite. Note that the string
-- must not contain any letters which aren't in the range of U+0000 -
-- U+00FF.
encodeBase64 :: String -> String
encodeBase64 = L8.unpack . encodeBase64LBS . L8.pack

-- |@'encodeBase64BS' bs@ strictly encodes a chunk of data to Base64.
encodeBase64BS :: ByteString -> ByteString
encodeBase64BS = encodeBlock

-- |@'encodeBase64LBS' lbs@ lazilly encodes a stream of data to
-- Base64. The string doesn't have to be finite.
encodeBase64LBS :: LazyByteString -> LazyByteString
encodeBase64LBS inLBS
    | L8.null inLBS = L8.empty
    | otherwise
        = let (blockParts', remain' ) = nextBlock 3 ([], inLBS)
              block'                  = B8.concat blockParts'
              blockLen'               = B8.length block'
              (block      , leftover) = if blockLen' < 3 then
                                            -- 最後の半端
                                            (block', B8.empty)
                                        else
                                            B8.splitAt (blockLen' - blockLen' `mod` 3) block'
              remain                  = if B8.null leftover then
                                            remain'
                                        else
                                            case remain' of
                                              LPS xs -> LPS (leftover:xs)
              encodedBlock             = encodeBlock block
              LPS encodedRemain        = encodeBase64LBS remain
          in
            LPS ([encodedBlock] ++ encodedRemain)


{- decode -------------------------------------------------------------------- -}

foreign import ccall unsafe "EVP_DecodeBlock"
        _DecodeBlock :: Ptr CChar -> Ptr CChar -> Int -> IO Int


decodeBlock :: ByteString -> ByteString
decodeBlock inBS
    = assert (B8.length inBS `mod` 4 == 0) $
      unsafePerformIO $
      unsafeUseAsCStringLen inBS $ \ (inBuf, inLen) ->
      createAndTrim (B8.length inBS) $ \ outBuf ->
      _DecodeBlock (castPtr outBuf) inBuf inLen

-- |@'decodeBase64' str@ lazilly decodes a stream of data from
-- Base64. The string doesn't have to be finite.
decodeBase64 :: String -> String
decodeBase64 = L8.unpack . decodeBase64LBS . L8.pack

-- |@'decodeBase64BS' bs@ strictly decodes a chunk of data from
-- Base64.
decodeBase64BS :: ByteString -> ByteString
decodeBase64BS = decodeBlock

-- |@'decodeBase64LBS' lbs@ lazilly decodes a stream of data from
-- Base64. The string doesn't have to be finite.
decodeBase64LBS :: LazyByteString -> LazyByteString
decodeBase64LBS inLBS
    | L8.null inLBS = L8.empty
    | otherwise
        = let (blockParts', remain' ) = nextBlock 4 ([], inLBS)
              block'                  = B8.concat blockParts'
              blockLen'               = B8.length block'
              (block      , leftover) = assert (blockLen' >= 4) $
                                        B8.splitAt (blockLen' - blockLen' `mod` 4) block'
              remain                  = if B8.null leftover then
                                            remain'
                                        else
                                            case remain' of
                                              LPS xs -> LPS (leftover:xs)
              decodedBlock            = decodeBlock block
              LPS decodedRemain       = decodeBase64LBS remain
          in
            LPS ([decodedBlock] ++ decodedRemain)