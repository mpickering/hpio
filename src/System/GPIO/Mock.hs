{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module System.GPIO.Mock
       ( AvailablePins
       , PinState(..)
       , PinStateMap
       , evalMock
       , execMock
       , runMock
       , runMockT
       ) where

import Control.Error.Util (note)
import Control.Monad.Except
import Control.Monad.RWS (MonadRWS, RWS, ask, get, put, runRWS, tell)
import Control.Monad.Trans.Free (iterT)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T (intercalate, pack)
import System.GPIO.Free (GpioF(..), GpioT, Pin(..), PinDescriptor(..), PinDirection(..), Value(..))

type AvailablePins = Set Pin

data PinState = PinState { dir :: !PinDirection, value :: !Value } deriving (Show, Eq)

type PinStateMap = Map PinDescriptor PinState

initialState :: PinState
initialState = PinState In Low

type MonadMock = MonadRWS AvailablePins [Text] PinStateMap

type Mock = RWS AvailablePins [Text] PinStateMap

tshow :: (Show a) => a -> Text
tshow = T.pack . show

runMockT :: (MonadError String m, MonadMock m) => (GpioT String) m a -> m a
runMockT = iterT run
  where
    run :: (MonadError String m, MonadMock m) => (GpioF String) (m a) -> m a

    run (Open p next) =
      do valid <- pinExists p
         case valid of
           False -> next (Left $ "Open failed: " ++ show p ++ " does not exist")
           True ->
             do say ["Open", tshow p]
                states <- get
                let d = PinDescriptor p
                put (Map.insert d initialState states)
                next (Right d)

    run (Close d next) =
      do valid <- validDescriptor d
         case valid of
           False -> next -- double-close is OK
           True ->
             do states <- get
                put (Map.delete d states)
                say ["Close", tshow d]
                next

    run (Direction d next) =
      do void $ checkDescriptor d
         eitherDirection <- pinDirection d
         case eitherDirection of
           Left e -> throwError e
           Right dir' -> next (Just dir')

    run (SetDirection d v next) =
      do void $ checkDescriptor d
         eitherState <- pinState d
         case eitherState of
           Left e -> throwError e
           Right s ->
             do states <- get
                put (Map.insert d (s { dir = v }) states)
                say ["Set direction:", tshow d, tshow v ]
                next

    run (ReadPin d next) =
      do void $ checkDescriptor d
         eitherValue <- pinValue d
         case eitherValue of
           Left e -> throwError e
           Right v -> next v

    run (WritePin d v next) =
      do void $ checkDescriptor d
         eitherState <- pinState d
         case eitherState of
           Left e -> throwError e
           Right s ->
             case dir s of
               In -> throwError (show d ++ " is configured for input")
               Out ->
                 do states <- get
                    put (Map.insert d (s { value = v }) states)
                    say ["Write:", tshow d, tshow v]
                    next

pinExists :: (MonadMock m) => Pin -> m Bool
pinExists p = ask >>= return . (Set.member p)

validDescriptor :: (MonadMock m) => PinDescriptor -> m Bool
validDescriptor d = get >>= return . (Map.member d)

checkDescriptor :: (MonadError String m, MonadMock m) => PinDescriptor -> m Bool
checkDescriptor d =
  do valid <- validDescriptor d
     when (not valid) $
       throwError $ "Pin descriptor " ++ show d ++ " is invalid"
     return valid

say :: (MonadMock m) => [Text] -> m ()
say t = tell $ [T.intercalate " " t]

pinF :: (MonadMock m) => (PinState -> a) -> PinDescriptor -> m (Either String a)
pinF f d =
  do states <- get
     return $ fmap f (note (show d ++ " is not a valid pin descriptor") (Map.lookup d states))

pinState :: (MonadMock m) => PinDescriptor -> m (Either String PinState)
pinState = pinF id

pinValue :: (MonadMock m) => PinDescriptor -> m (Either String Value)
pinValue = pinF value

pinDirection :: (MonadMock m) => PinDescriptor -> m (Either String PinDirection)
pinDirection = pinF dir

-- | Run a GpioT program in a pure environment mimicking IO;
-- exceptions are manifested as 'Either' 'String' 'a'.
runMock :: AvailablePins -> (GpioT String) (ExceptT String Mock) a -> (Either String a, PinStateMap, [Text])
runMock pins action = runRWS (runExceptT $ runMockT action) pins Map.empty

-- | Evaluate a GpioT program in the 'Mock' monad and return the final
-- value and output, discarding the final state.
evalMock :: AvailablePins -> (GpioT String) (ExceptT String Mock) a -> (Either String a, [Text])
evalMock pins action =
  let (a, _, w) = runMock pins action
  in (a, w)

-- | Evaluate a GpioT program in the 'Mock' monad and return the final
-- state and output, discarding the final value.
execMock :: AvailablePins -> (GpioT String) (ExceptT String Mock) a -> (PinStateMap, [Text])
execMock pins action =
  let (_, s, w) = runMock pins action
  in (s, w)
