\ignore{

\begin{code}
import SExpr
import Stack

mapSucc PSusp = PSusp
mapSucc (PRes x) = PRes (succ x) 
mapSucc (x :> xs) = succ x :> mapSucc xs

dislikeThreshold _ = 0

\end{code}

}
\section{Parsing}
\label{sec:parsing}
\textmeta{Termination if there is no recursive call before parsing one token}

We kept the details of actual parsing out of the discussion so far.
This is for good reason: the machinery for incremental computation
and reuse of partial results is independent from such details. Indeed,
given any procedure to compute structured values from a linear
input of symbols, one can use the procedure described above to
transform it into an incremental algorithm.

\subsection{Disjunction}
\label{sec:disjunction}

However, the most common way to produce such structured values is
by \emph{parsing} the input string. To support convenient parsing,
we can introduce a disjunction operator, exactly as \citet{hughes_polish_2003}
do: the addition of the |Susp| operator does not
undermine their treatment of disjunction in any way.

\begin{meta}
The zipper cannot go beyond an unresolved disjunction. That is OK
if we assume that the parser has not much lookahead.
\end{meta}

\subsection{Error correction}


Disjuction is not very useful unless coupled with \emph{failure} (otherwise all
branches would be equivalent). Still, the (unrestricted) usage of failure is
problematic for our application: the online property requires at least one
branch to yield a successful outcome. Indeed, since the |evalR| function
\emph{must} return a result (we want a total function!), the parser must a
conjure up a suitable result for \emph{any} input.

If the grammar is sufficiently permissive, no error correction in the parsing
algorithm itself is necessary. This is the case for our simple s-expression parser.
However, most interesting grammars produce a highly structured result, and are
correspondingly restrictive on the input they accept. Augmenting the parser with
error correction is therefore desirable.

We can do so by introducing an other constructor in the |Parser| type to denote
less desirable parses. The intent is to extend the grammar with more permissive rules
to deal with incorrect input, tagging those as less desirable. The parsing algorithm
can then maximize the desirability of the set of rules used for parsing a given
fragment of input.

\begin{code}
data Parser s a where
    Pure   :: a                                  -> Parser s a
    (:*:)  :: Parser s (b -> a) -> Parser s b    -> Parser s a
    Case   :: Parser s a -> (s -> Parser s a)    -> Parser s a
    Disj   :: Parser s a -> Parser s a           -> Parser s a
    Yuck   :: Parser s a                         -> Parser s a
\end{code}

At each disjunction point, the evaluation function will have to choose between
two alternatives. Since we want online behavior, we cannot afford to look
further than a few symbols ahead to decide which parse might be the best.
(Additionally the number of potential recovery paths grows exponentially with
the amount of lookahead). We use the widespread technique \citep[chapter
8]{bird_algebra_1997} to thin out search after some constant, small amount of
lookahead.


\begin{figure*}
\include{progress}
\caption{
A parsing process and associated progress information. The process has been fed a whole input, so it is free of |Susp|
constructors.
It is also stripped of result information for clarity (|Push|, |App|), since it is irrelevant to the
computation of progress information. Each constructor is represented by a circle, and their arguments
by arrows.
The progress information accociated with the process is written in the rectangle
beside the node that starts the process. To decide which path to take at the
disjunction, only the gray nodes will be forced, if the desirability difference
is 1 for lookahead 1.
}
\label{fig:progress}
\end{figure*}

In contrast to \citet{hughes_polish_2003}, we do not compute the best path by
direct manipulation of the polish representation. Instead, we introduce a new
datatype which represents the ``progress'' information only.

\begin{code}
data Progress = PSusp | PRes Int | !Int :> Progress
\end{code}

\textmeta{Oops, We can't really use |fix Dislike| for failure, because we use
Ints, instead of Peano naturals.}

This data structure is similar to a list where the $n^{th}$ element tells how
much we dislike to take this path after shifting $n$ symbols following it,
\emph{assuming we take the best choice at each disjunction}.

The difference with a simple list is that progress information may end with
success or suspension, depending on whether the process reaches |Done| or
|Susp|.

Given two (terminated) |Progress| values, it is possible to determine which one
is best by demanding only a prefix of each, using our thinning heuristic. 

We can now use this information to determine which path to take when facing a
disjunction. In turn, this allows to compute the progress information on the
basis of the polish representation only.


\begin{figure}
\begin{code}
data Polish s a where
    Push     ::  a -> Polish s r                      ->  Polish s (a :< r)
    App      ::  Polish s ((b -> a) :< b :< r)
                                                      ->  Polish s (a :< r)
    Done     ::                                           Polish s Nil
    Shift    ::  Polish s a                           ->  Polish s a
    Sus      ::  Polish s a -> (s -> Polish s a) 
                                                      ->  Polish s a
    Best     ::  Ordering -> Progress -> 
                   Polish s a -> Polish s a           ->  Polish s a
    Dislike  ::  Polish s a                           ->  Polish s a

progress :: Polish s r -> Progress
progress (Push _ p)       = progress p                          
progress (App p)          = progress p                          
progress (Shift p)        = 0 :> progress p                     
progress (Done)           = PRes 0
progress (Dislike p)      = mapSucc (progress p)                
progress (Sus _ _)        = PSusp                               
progress (Best _ pr _ _)  = pr                                  

toP :: Parser s a -> (Polish s r -> Polish s (a :< r))
toP (Case a f)  = \fut -> Sus  (toP a fut)
                               (\s -> toP (f s) fut)
toP (f :*: x)   = App . toP f . toP x
toP (Pure x)    = Push x
toP (Disj a b)  = \fut -> mkBest (toP a fut) (toP b fut)
toP (Yuck p)    = Dislike . toP p 

mkBest :: Polish s a -> Polish s a -> Polish s a
mkBest p q = 
   let  (choice, pr) = better 0 (progress p) (progress q) 
   in   Best choice pr p q

better :: Int -> Progress -> Progress -> (Ordering, Progress)
-- compute which progress is the better one (with a give lookahead), and return it.
\end{code}
\caption{Handling disjunction}
\end{figure}

Proceeding exactly as such is horribly inefficient. We can use the classic
trick \cite{swierstra} to cache the progress information in the |Polish|
representation. For simplicity, we cache the information only at disjunction
nodes where we also remember which path is best to take.

We finally see why the |Polish| representation is so important:
the progress information cannot be associated to a |Parser|, because
it may depend on whatever parser \emph{follows} it. This is not
an issue in the |Polish| representation, because it is unfolded until
the end of the parsing.


Our technique can be re-formulated as lazy dynamic programming, in the style of
\citet{allison_lazy_1992}. We first define a full tree of possibilities (Polish
expressions with disjunction), then we compute a progress information that we
tie to it, for each node; finally, finding the best path is a matter of looking
only at a subset of the information we constructed, using any suitable
heuristic. The cut-off heuristic makes sure that only a part of the
exponentially big data structure is demanded. Thanks to lazy evaluation, only
that small will be actually constructed.

\subsection{Thinning out results and ambiguous grammars}

A sound basis for thinnig out less desirable paths is to discard those which
are less preferrable by some amount. In order to pick one path after a constant
amount of lookahead $l$, we must set this difference to 0 when comparing the
$l^{th}$ element of the progress information, so that the parser can pick a
particular path, and return results. Unfortunately, applying this rule strictly
is dangerous in if the grammar requires a large lookahead, and in particular if
it is ambiguous. In that case, the algorithm can possibly commit to a prefix which will
plead to errors while processing the rest of the output, while another prefix
would match the rest of the input and yield no error. In the present version of
the library we avoid the problem by keeping all valid prefixes.

\begin{code}
better _ PSusp _ = (EQ, PSusp)
better _ _ PSusp = (EQ, PSusp)
better _ (PRes x) (PRes y) = 
   if x <= y then (LT, PRes x) else (GT, PRes y)
better lk xs@(PRes x) (y:>ys) = 
   if x == 0 || y-x > dislikeThreshold lk 
   then (LT, xs) 
   else min x y +> better (lk+1) xs ys
better lk (y:>ys) xs@(PRes x) = 
   if x == 0 || y-x > dislikeThreshold lk 
   then (GT, xs) 
   else min x y +> better (lk+1) ys xs
better lk (x:>xs) (y:>ys)
    | x == 0 && y == 0 = rec
    | y - x > threshold = (LT, x:>xs)
    | x - y > threshold = (GT, y:>ys)
    | otherwise = rec
    where threshold = dislikeThreshold lk
          rec = min x y +> better (lk + 1) xs ys
x +> ~(ordering, xs) = (ordering, x :> xs)
\end{code}


The user of the parsing library has to be aware of this issue when designing
grammars: it can affect the performance of the algorithm to a great extent.

\textmeta{Final version of evalL?}