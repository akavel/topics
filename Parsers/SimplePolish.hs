-- Copyright (c) JP Bernardy 2008
-- | This is a re-implementation of the "Polish Parsers" in a clearer way. (imho)
{-# OPTIONS -fglasgow-exts #-}
module SimplePolish (Process, Void, 
                     symbol, eof, lookNext, runPolish, 
                     runP, progress, evalR,
                     P) where
import Control.Applicative
import Data.List hiding (map, minimumBy)
import Data.Char
import Data.Maybe (listToMaybe)

data Void

data Steps a where
    Val   :: a -> Steps r               -> Steps (a,r)
    App   :: (Steps (b -> a,(b,r)))      -> Steps (a,r)
    Done  ::                               Steps Void
    Shift ::           Steps a        -> Steps a
    Fail ::                                Steps a
    Best :: Ordering -> Progress -> Steps a -> Steps a -> Steps a

data Progress = PFail | PDone | PShift Progress
    deriving Show

better :: Progress -> Progress -> (Ordering, Progress)
better PFail p = (GT, p) -- avoid failure
better p PFail = (LT, p)
better PDone PDone = (EQ, PDone)
better (PShift p) (PShift q) = pstep (better p q)

pstep ~(ordering, xs) = (ordering, PShift xs)

progress :: Steps a -> Progress
progress (Val _ p) = progress p
progress (App p) = progress p
progress (Shift p) = PShift (progress p)
progress (Done) = PDone
progress (Fail) = PFail
progress (Best _ pr _ _) = pr

-- | Right-eval a fully defined process
evalR :: Steps (a,r) -> (a, Steps r)
evalR z@(Val a r) = (a,r)
evalR (App s) = let (f, s') = evalR s
                    (x, s'') = evalR s'
                in (f x, s'')
evalR (Shift v) = evalR v
evalR (Fail) = error "evalR: No parse!"
evalR (Best choice _ p q) = case choice of
    LT -> evalR p
    GT -> evalR q
    EQ -> error $ "evalR: Ambiguous parse: " ++ show p ++ " ~~~ " ++ show q

-- | A parser. (This is actually a parsing process segment)
newtype P s a = P {fromP :: forall b r. ([s] -> Steps r)  -> ([s] -> Steps (a,r))}

-- | A complete process
type Process a = Steps (a,Void)

instance Functor (P s) where
    fmap f x = pure f <*> x

instance Applicative (P s) where
    P f <*> P x = P ((App .) . f . x)
    pure x = P (\fut input -> Val x $ fut input)

instance Alternative (P s) where
    empty = P $ \_fut _input -> Fail
    P a <|> P b = P $ \fut input -> iBest (a fut input) (b fut input)
        where iBest p q = let ~(choice, pr) = better (progress p) (progress q) in Best choice pr p q

runP :: forall s a. P s a -> [s] -> Process a
runP (P p) input = p (\_input -> Done) input

-- | Run a parser.
runPolish :: forall s a. P s a -> [s] -> a
runPolish p input = fst $ evalR $ runP p input

-- | Parse a symbol
symbol :: (s -> Bool) -> P s s
symbol f = P $ \fut input -> case input of
    [] -> Fail -- This is the eof!
    (s:ss) -> if f s then Shift (Val s (fut ss))
                     else Fail

-- | Parse the eof
eof :: P s ()
eof = P $ \fut input -> case input of
    [] -> Shift (Val () $ fut input)
    _ -> Fail

--------------------------------------------------
-- Extra stuff


lookNext :: (Maybe s -> Bool) -> P s ()
lookNext f = P $ \fut input ->
   if (f $ listToMaybe input) then Val () (fut input)
                              else Fail
        

instance Show (Steps a) where
    show (Val _ p) = "v" ++ show p
    show (App p) = "*" ++ show p
    show (Done) = "1"
    show (Shift p) = ">" ++ show p
    show (Fail) = "0"
    show (Best _ _ p q) = "(" ++ show p ++ ")" ++ show q

-- | Pre-compute a left-prefix of some steps (as far as possible)
evalL :: Steps a -> Steps a
evalL (Shift p) = evalL p
evalL (Val x r) = Val x (evalL r)
evalL (App f) = case evalL f of
                  (Val a (Val b r)) -> Val (a b) r
                  (Val f1 (App (Val f2 r))) -> App (Val (f1 . f2) r)
                  r -> App r
evalL x@(Best choice _ p q) = case choice of
    LT -> evalL p
    GT -> evalL q
    EQ -> x -- don't know where to go: don't speculate on evaluating either branch.
evalL x = x


------------------

data Expr = V Int | Add Expr Expr
            deriving Show

sym x = symbol (== x)

pExprParen = symbol (== '(') *> pExprTop <* symbol (== ')')

pExprVal = V <$> toInt <$> symbol (isDigit)
    where toInt c = ord c - ord '0'

pExprAtom = pExprVal <|> pExprParen

pExprAdd = pExprAtom <|> Add <$> pExprAtom <*> (symbol (== '+') *> pExprAdd) 

pExprTop = pExprAdd

pExpr = pExprTop <* eof
{-
syms [] = pure ()
syms (s:ss) = sym s *> syms ss

pTag  = sym '<' *> many (symbol (/= '>')) <* sym '>'
pTag' s = sym '<' *> syms s <* sym '>'

pTagged t p = do
    open <- pTag
    p <* pTag' open
    

p0 = (pure 1 <* sym 'a') <|> (pure 2)

p1 = \x -> if x == 2 then sym 'a' *> pure 3 else sym 'b' *> pure 4

test = runPolish (p0 >>= p1) "ab"
-}