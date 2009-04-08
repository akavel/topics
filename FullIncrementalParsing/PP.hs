{-# LANGUAGE MultiParamTypeClasses #-}

import Data.Char
import Data.List
import Data.Maybe
import Data.FingerTree
import Data.Monoid
-- import Data.Sequence

data P s where
     Sym :: (s -> Bool) -> P s 
     (:*:) :: P s -> P s -> P s
     (:|:) :: P s -> P s -> P s
     (:>) :: String -> P sc


----------------------------



type Check = El -> Bool
data El = S Char | Nt Int [El]
    deriving (Show,Eq)

data Rule = Rule Int [Check] 

type Seq = [El]

type Grammar = [Rule]

type State = [Seq]

match :: [Check] -> [El] -> Bool
match [] _ = True
match (x:xs) (y:ys) = x y && match xs ys
match _ _ = False


apply :: Rule -> Seq -> Maybe Seq
apply (Rule n xs) ys = listToMaybe [prefix ++ [Nt n matched] ++ suffix |
                                    (prefix,rest) <- zip (inits ys) (tails ys), 
                                    match xs rest, let (matched,suffix) = splitAt (length xs) rest]
        
applyAll :: Grammar -> Seq -> Seq
applyAll g s = foldr (\rule -> tillConverge (apply rule)) s g

tillConverge :: (a -> Maybe a) -> (a -> a)
tillConverge f a = case f a of
    Nothing -> a
    Just x -> tillConverge f x

merge :: Grammar -> State -> State -> State
merge g ls rs = nub [applyAll g (l ++ r) | l <- ls, r <- rs]


newtype M = M State deriving Show

instance Measured M Char where
    measure c = M [[S c]]

instance Monoid M where
    mappend (M s) (M t) = M (merge grammar s t)
    mempty = M [[]]

------------------------------

sym c (S c') = c == c'
sym _ _ = False

symbol f (S c) = f c
symbol _ _ = False

nt x (Nt y _) = x == y
nt _ _ = False

grammar = [Rule 1 [sym '(', nt 1, sym ')'],
           Rule 1 [nt 1, sym '+', nt 1],
           Rule 1 [symbol isDigit]
          ]

{-

a b 

asd 

f x = a + b
df
 
df
s

gg


-}


test = measure $ fromList $ "1+((2+4)+(5+4))" ++ concat (replicate 1000 "+1+((2+4)+(5+4))")



