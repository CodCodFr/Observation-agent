 # ! / b i n / b a s h 
 
 #   - - -   C o n f i g u r a t i o n   d u   S c r i p t   d e   S e t u p   - - - 
 #   U R L   d e   l ' i m a g e   D o c k e r   d e   v o t r e   a g e n t   s u r   G i t H u b   C o n t a i n e r   R e g i s t r y   ( G H C R ) 
 D O C K E R _ I M A G E _ N A M E = " g h c r . i o / c o d c o d f r / o b s e r v a t i o n - a g e n t : l a t e s t " 
 
 A G E N T _ P O R T = " 3 0 0 0 "   #   P o r t   s u r   l e q u e l   l ' a g e n t   é c o u t e r a   D A N S   l e   c o n t e n e u r   D o c k e r 
 Y O U R _ S S H _ I P = " 1 5 2 . 5 3 . 1 0 4 . 1 9 "   #   I P   p u b l i q u e   d e   v o t r e   s e r v e u r   p r i n c i p a l   ( À   R E M P L A C E R   I M P É R A T I V E M E N T ) 
 Y O U R _ B A C K E N D _ I P = " c o d c o d . f r "   #   I P   p u b l i q u e   d e   v o t r e   s e r v e u r   p r i n c i p a l   ( À   R E M P L A C E R   I M P É R A T I V E M E N T ) 
 S S H _ T U N N E L _ U S E R = " t u n n e l _ u s e r "   #   U t i l i s a t e u r   S S H   c r é é   s u r   v o t r e   b a c k e n d   p o u r   l e   t u n n e l 
 B A C K E N D _ P O R T = " 7 9 9 9 "   #   P o r t   d e   v o t r e   b a c k e n d   N o d e . j s   ( c e l u i   q u i   r e ç o i t   l a   c l é   p u b l i q u e ,   e x :   3 0 0 0 ) 
 S S H _ P O R T = " 2 2 3 2 6 "   #   L e   p o r t   S S H   d e   v o t r e   s e r v e u r   b a c k e n d 
 
 #   R é c u p é r e r   l e s   a r g u m e n t s   p a s s é s   p a r   l a   c o m m a n d e   c u r l 
 A P I _ S E C R E T _ F O R _ A G E N T = " $ 1 " 
 V P S _ I D E N T I F I E R = " $ 2 " 
 
 #   - - -   C o n f i g u r a t i o n   d u   L o g   - - - 
 L O G _ F I L E = " / v a r / l o g / v p s - a g e n t - s e t u p . l o g " 
 e x e c   >   > ( t e e   - a   " $ { L O G _ F I L E } " )   2 > & 1 
 e c h o   " - - -   D é b u t   d u   p r o c e s s u s   d ' i n s t a l l a t i o n   d e   l ' a g e n t   V P S   a v e c   D o c k e r   e t   t u n n e l   S S H   - - - " 
 e c h o   " D a t e :   $ ( d a t e ) " 
 
 #   V é r i f i c a t i o n   d e s   p r é - r e q u i s 
 i f   [   " $ E U I D "   - n e   0   ] ;   t h e n 
         e c h o   " C e   s c r i p t   d o i t   ê t r e   e x é c u t é   a v e c   l e s   p r i v i l è g e s   r o o t .   U t i l i s e z   ' s u d o ' . " 
         e x i t   1 
 f i 
 i f   [   - z   " $ A P I _ S E C R E T _ F O R _ A G E N T "   ]   | |   [   - z   " $ V P S _ I D E N T I F I E R "   ] ;   t h e n 
         e c h o   " E r r e u r   :   L e s   a r g u m e n t s   A P I _ S E C R E T   e t   V P S _ I D E N T I F I E R   s o n t   m a n q u a n t s . " 
         e c h o   " U t i l i s a t i o n :   c u r l   . . .   |   s u d o   b a s h   - s   - -   \ " < A P I _ S E C R E T > \ "   \ " < V P S _ I D E N T I F I E R > \ " " 
         e x i t   1 
 f i 
 
 T U N N E L _ R U N _ U S E R = $ { S U D O _ U S E R : - r o o t } 
 H O M E _ D I R _ T U N N E L _ U S E R = $ ( e v a l   e c h o   " ~ $ { T U N N E L _ R U N _ U S E R } " ) 
 
 i f   [   - f   / e t c / o s - r e l e a s e   ] ;   t h e n 
         .   / e t c / o s - r e l e a s e 
         O S = $ I D 
 e l s e 
         e c h o   " D i s t r i b u t i o n   L i n u x   n o n   d é t e c t é e .   N e   p e u t   p a s   c o n t i n u e r . " 
         e x i t   1 
 f i 
 e c h o   " S y s t è m e   d ' e x p l o i t a t i o n   d é t e c t é :   $ O S " 
 e c h o   " L e   t u n n e l   s e r a   e x é c u t é   s o u s   l ' u t i l i s a t e u r :   $ { T U N N E L _ R U N _ U S E R } " 
 e c h o   " C h e m i n   d e   b a s e   d e s   c l é s   S S H   p o u r   l e   t u n n e l :   $ { H O M E _ D I R _ T U N N E L _ U S E R } / . s s h / " 
 
 #   I n s t a l l a t i o n   d e   D o c k e r   e t   O p e n S S H   C l i e n t 
 e c h o   " I n s t a l l a t i o n   d e s   d é p e n d a n c e s   ( D o c k e r ,   O p e n S S H   C l i e n t ,   j q ) . . . " 
 i f   [ [   " $ O S "   = =   " d e b i a n "   | |   " $ O S "   = =   " u b u n t u "   ] ] ;   t h e n 
         e x p o r t   D E B I A N _ F R O N T E N D = n o n i n t e r a c t i v e 
         a p t - g e t   u p d a t e   - y   & &   a p t - g e t   i n s t a l l   - y   c a - c e r t i f i c a t e s   c u r l   g n u p g   o p e n s s h - c l i e n t   j q   | |   {   e c h o   " É c h e c   d e   l ' i n s t a l l a t i o n   d e s   p r é - r e q u i s   A P T . " ;   e x i t   1 ;   } 
         
         i n s t a l l   - m   0 7 5 5   - d   / e t c / a p t / k e y r i n g s 
         c u r l   - f s S L   h t t p s : / / d o w n l o a d . d o c k e r . c o m / l i n u x / d e b i a n / g p g   |   g p g   - - d e a r m o r   - o   / e t c / a p t / k e y r i n g s / d o c k e r . g p g 
         c h m o d   a + r   / e t c / a p t / k e y r i n g s / d o c k e r . g p g 
         
         e c h o   " d e b   [ a r c h = $ ( d p k g   - - p r i n t - a r c h i t e c t u r e )   s i g n e d - b y = / e t c / a p t / k e y r i n g s / d o c k e r . g p g ]   h t t p s : / / d o w n l o a d . d o c k e r . c o m / l i n u x / d e b i a n   $ ( .   / e t c / o s - r e l e a s e   & &   e c h o   " $ V E R S I O N _ C O D E N A M E " )   s t a b l e "   |   s u d o   t e e   / e t c / a p t / s o u r c e s . l i s t . d / d o c k e r . l i s t   >   / d e v / n u l l 
         
         a p t - g e t   u p d a t e   - y   & &   a p t - g e t   i n s t a l l   - y   d o c k e r - c e   d o c k e r - c e - c l i   c o n t a i n e r d . i o   | |   {   e c h o   " É c h e c   d e   l ' i n s t a l l a t i o n   d e   D o c k e r   C E . " ;   e x i t   1 ;   } 
 e l i f   [ [   " $ O S "   = =   " c e n t o s "   | |   " $ O S "   = =   " r h e l "   | |   " $ O S "   = =   " r o c k y "   ] ] ;   t h e n 
         y u m   i n s t a l l   - y   y u m - u t i l s   d e v i c e - m a p p e r - p e r s i s t e n t - d a t a   l v m 2   o p e n s s h - c l i e n t s   j q   | |   {   e c h o   " É c h e c   d e   l ' i n s t a l l a t i o n   d e s   p r é - r e q u i s   Y U M . " ;   e x i t   1 ;   } 
         y u m - c o n f i g - m a n a g e r   - - a d d - r e p o   h t t p s : / / d o w n l o a d . d o c k e r . c o m / l i n u x / c e n t o s / d o c k e r - c e . r e p o 
         y u m   i n s t a l l   - y   d o c k e r - c e   d o c k e r - c e - c l i   c o n t a i n e r d . i o   | |   {   e c h o   " É c h e c   d e   l ' i n s t a l l a t i o n   d e   D o c k e r   C E . " ;   e x i t   1 ;   } 
         s y s t e m c t l   s t a r t   d o c k e r 
         s y s t e m c t l   e n a b l e   d o c k e r 
 e l s e 
         e c h o   " I n s t a l l a t i o n   d e   D o c k e r   n o n   p r i s e   e n   c h a r g e   p o u r   c e t t e   d i s t r i b u t i o n .   V e u i l l e z   i n s t a l l e r   D o c k e r   m a n u e l l e m e n t . " 
         e x i t   1 
 f i 
 e c h o   " D é p e n d a n c e s   e s s e n t i e l l e s   ( D o c k e r ,   j q )   i n s t a l l é e s . " 
 
 #   D é m a r r a g e   e t   c o n f i g u r a t i o n   d e   l ' a g e n t   D o c k e r 
 e c h o   " D é m a r r a g e   e t   c o n f i g u r a t i o n   d e   l ' a g e n t   D o c k e r . . . " 
 d o c k e r   s t o p   v p s - a g e n t - c o n t a i n e r   >   / d e v / n u l l   2 > & 1   | |   t r u e 
 d o c k e r   r m   v p s - a g e n t - c o n t a i n e r   >   / d e v / n u l l   2 > & 1   | |   t r u e 
 d o c k e r   p u l l   " $ D O C K E R _ I M A G E _ N A M E "   | |   {   e c h o   " É c h e c   d u   p u l l   d e   l ' i m a g e   D o c k e r . " ;   e x i t   1 ;   } 
 d o c k e r   r u n   - d   - - r e s t a r t = a l w a y s   - - n a m e   v p s - a g e n t - c o n t a i n e r   - e   A P I _ S E C R E T = " $ A P I _ S E C R E T _ F O R _ A G E N T "   - e   P O R T = " $ A G E N T _ P O R T "   - p   1 2 7 . 0 . 0 . 1 : " $ A G E N T _ P O R T " : " $ A G E N T _ P O R T "   " $ D O C K E R _ I M A G E _ N A M E "   | |   {   e c h o   " É c h e c   d u   l a n c e m e n t   d u   c o n t e n e u r   D o c k e r . " ;   e x i t   1 ;   } 
 e c h o   " C o n t e n e u r   D o c k e r   d e   l ' a g e n t   l a n c é . " 
 
 #   G é n é r a t i o n   d e   l a   p a i r e   d e   c l é s   S S H   p o u r   l e   t u n n e l 
 e c h o   " G é n é r a t i o n   d e   l a   p a i r e   d e   c l é s   S S H   p o u r   l e   t u n n e l . . . " 
 S S H _ K E Y _ D I R = " $ { H O M E _ D I R _ T U N N E L _ U S E R } / . s s h " 
 S S H _ K E Y _ P A T H = " $ { S S H _ K E Y _ D I R } / i d _ r s a _ v p s _ t u n n e l " 
 m k d i r   - p   " $ { S S H _ K E Y _ D I R } "   | |   {   e c h o   " É c h e c   d e   l a   c r é a t i o n   d u   r é p e r t o i r e   $ { S S H _ K E Y _ D I R } . " ;   e x i t   1 ;   } 
 c h o w n   " $ { T U N N E L _ R U N _ U S E R } " : " $ { T U N N E L _ R U N _ U S E R } "   " $ { S S H _ K E Y _ D I R } "   | |   {   e c h o   " É c h e c   d u   c h o w n   s u r   $ { S S H _ K E Y _ D I R } . " ;   e x i t   1 ;   } 
 c h m o d   7 0 0   " $ { S S H _ K E Y _ D I R } "   | |   {   e c h o   " É c h e c   d u   c h m o d   s u r   $ { S S H _ K E Y _ D I R } . " ;   e x i t   1 ;   } 
 r m   - f   " $ { S S H _ K E Y _ P A T H } "   " $ { S S H _ K E Y _ P A T H } . p u b " 
 s u d o   - u   " $ { T U N N E L _ R U N _ U S E R } "   s s h - k e y g e n   - t   r s a   - b   4 0 9 6   - f   " $ { S S H _ K E Y _ P A T H } "   - N   " "   | |   {   e c h o   " É c h e c   d e   l a   g é n é r a t i o n   d e   l a   c l é   S S H . " ;   e x i t   1 ;   } 
 c h m o d   6 0 0   " $ { S S H _ K E Y _ P A T H } " 
 c h m o d   6 0 0   " $ { S S H _ K E Y _ P A T H } . p u b " 
 P U B L I C _ K E Y _ F O R _ T U N N E L = $ ( c a t   " $ { S S H _ K E Y _ P A T H } . p u b " ) 
 e c h o   " C l é   p u b l i q u e   d u   t u n n e l   g é n é r é e :   $ { P U B L I C _ K E Y _ F O R _ T U N N E L } " 
 
 #   E n v o i   d e   l a   C l é   P u b l i q u e   à   v o t r e   B a c k e n d 
 e c h o   " E n v o i   d e   l a   c l é   p u b l i q u e   d u   t u n n e l   à   v o t r e   b a c k e n d . . . " 
 B A C K E N D _ A P I _ U R L = " h t t p s : / / $ { Y O U R _ B A C K E N D _ I P } : $ { B A C K E N D _ P O R T } / a g e n t / r e g i s t e r - t u n n e l - k e y " 
 A U T H _ T O K E N _ F O R _ B A C K E N D = $ ( e c h o   - n   " $ A P I _ S E C R E T _ F O R _ A G E N T "   |   s h a 2 5 6 s u m   |   a w k   ' { p r i n t   $ 1 } ' ) 
 c u r l _ o u t p u t = $ ( c u r l   - s   - X   P O S T   - H   " C o n t e n t - T y p e :   a p p l i c a t i o n / j s o n "   - H   " A u t h o r i z a t i o n :   B e a r e r   $ A U T H _ T O K E N _ F O R _ B A C K E N D "   - d   " { \ " v p s I d \ " :   \ " $ V P S _ I D E N T I F I E R \ " ,   \ " p u b l i c K e y \ " :   \ " $ P U B L I C _ K E Y _ F O R _ T U N N E L \ " } "   " $ B A C K E N D _ A P I _ U R L " ) 
 
 i f   [   $ ?   - n e   0   ] ;   t h e n 
         e c h o   " É c h e c   d e   l a   r e q u ê t e   c U R L   v e r s   l e   b a c k e n d .   R é p o n s e :   $ { c u r l _ o u t p u t } " 
         e x i t   1 
 e l s e 
         e c h o   " R e q u ê t e   c U R L   e n v o y é e .   R é p o n s e :   $ { c u r l _ o u t p u t } " 
 f i 
 
 #   E x t r a c t   t h e   t u n n e l P o r t   f r o m   t h e   J S O N   r e s p o n s e 
 T U N N E L _ P O R T _ G E T = $ ( e c h o   " $ { c u r l _ o u t p u t } "   |   j q   - r   ' . t u n n e l P o r t ' ) 
 
 i f   [   $ ?   - n e   0   ]   | |   [   - z   " $ T U N N E L _ P O R T _ G E T "   ]   | |   [   " $ T U N N E L _ P O R T _ G E T "   =   " n u l l "   ] ;   t h e n 
         e c h o   " E r r e u r :   I m p o s s i b l e   d ' o b t e n i r   u n   p o r t   d e   t u n n e l   v a l i d e   d u   b a c k e n d . "   > & 2 
         e x i t   1 
 f i 
 
 #   D é m a r r a g e   d u   t u n n e l   S S H   i n v e r s é   a v e c   S y s t e m d 
 e c h o   " L a n c e m e n t   d u   t u n n e l   S S H   i n v e r s é   a v e c   S y s t e m d . . . " 
 S E R V I C E _ N A M E = " v p s - t u n n e l . s e r v i c e " 
 S S H _ C O M M A N D _ A R G S = " - N   - T   - R   0 . 0 . 0 . 0 : $ { T U N N E L _ P O R T _ G E T } : l o c a l h o s t : $ { A G E N T _ P O R T }   - p   $ { S S H _ P O R T }   - i   $ { S S H _ K E Y _ P A T H }   - o   E x i t O n F o r w a r d F a i l u r e = y e s   - o   S e r v e r A l i v e I n t e r v a l = 6 0   - o   S e r v e r A l i v e C o u n t M a x = 3   - o   B a t c h M o d e = y e s   $ { S S H _ T U N N E L _ U S E R } @ $ { Y O U R _ S S H _ I P } " 
 S E R V I C E _ F I L E = " / e t c / s y s t e m d / s y s t e m / $ { S E R V I C E _ N A M E } " 
 
 e c h o   " T u n n e l   p o r t   ' $ { T U N N E L _ P O R T _ G E T } '   r e g i s t e r e d   a n d   c o n f i g u r e d . " 
 
 s y s t e m c t l   s t o p   " $ { S E R V I C E _ N A M E } "   >   / d e v / n u l l   2 > & 1   | |   t r u e 
 s y s t e m c t l   d i s a b l e   " $ { S E R V I C E _ N A M E } "   >   / d e v / n u l l   2 > & 1   | |   t r u e 
 
 #   C o r r e c t i o n :   U t i l i s a t i o n   d e   l a   b o n n e   s y n t a x e   p o u r   l ' e x p a n s i o n   d e s   v a r i a b l e s   d a n s   l e   b l o c   E O F 
 c a t   >   " $ { S E R V I C E _ F I L E } "   < <   E O F 
 [ U n i t ] 
 D e s c r i p t i o n = S S H   T u n n e l   f o r   V P S   A g e n t 
 A f t e r = n e t w o r k . t a r g e t 
 
 [ S e r v i c e ] 
 E x e c S t a r t P r e = / u s r / b i n / t e s t   - f   $ { S S H _ K E Y _ P A T H } 
 E x e c S t a r t = / u s r / b i n / s s h   $ { S S H _ C O M M A N D _ A R G S } 
 U s e r = $ { T U N N E L _ R U N _ U S E R } 
 R e s t a r t = a l w a y s 
 R e s t a r t S e c = 1 0 
 
 [ I n s t a l l ] 
 W a n t e d B y = m u l t i - u s e r . t a r g e t 
 E O F 
 
 s y s t e m c t l   d a e m o n - r e l o a d   | |   {   e c h o   " É c h e c   d e   ' s y s t e m c t l   d a e m o n - r e l o a d ' . " ;   e x i t   1 ;   } 
 s y s t e m c t l   e n a b l e   " $ { S E R V I C E _ N A M E } "   | |   {   e c h o   " É c h e c   d e   ' s y s t e m c t l   e n a b l e ' . " ;   e x i t   1 ;   } 
 s y s t e m c t l   s t a r t   " $ { S E R V I C E _ N A M E } "   | |   {   e c h o   " É c h e c   d e   ' s y s t e m c t l   s t a r t ' . " ;   e x i t   1 ;   } 
 
 e c h o   " T u n n e l   S S H   i n v e r s é   l a n c é   e t   c o n f i g u r é   p o u r   d é m a r r e r   a u   b o o t   a v e c   S y s t e m d . " 
 
 #   C o n f i g u r a t i o n   d u   p a r e - f e u   ( U F W ) 
 e c h o   " C o n f i g u r a t i o n   d u   p a r e - f e u   ( U F W ) . . . " 
 i f   c o m m a n d   - v   u f w   & >   / d e v / n u l l ;   t h e n 
         u f w   a l l o w   " $ { S S H _ P O R T } / t c p "   | |   {   e c h o   " É c h e c   d e   l ' o u v e r t u r e   d u   p o r t   S S H   d a n s   U F W . " ;   e x i t   1 ;   } 
         u f w   - - f o r c e   e n a b l e   | |   {   e c h o   " É c h e c   d e   l ' a c t i v a t i o n   d e   U F W . " ;   e x i t   1 ;   } 
         e c h o   " U F W   c o n f i g u r é .   S e u l   l e   p o r t   S S H   ( $ { S S H _ P O R T } )   e s t   o u v e r t   p o u r   l ' e x t é r i e u r . " 
 e l s e 
         e c h o   " U F W   n o n   i n s t a l l é .   I g n o r e   l a   c o n f i g u r a t i o n   d u   p a r e - f e u .   V e u i l l e z   v o u s   a s s u r e r   q u e   l e   p o r t   S S H   e s t   o u v e r t . " 
 f i 
 
 i f   [ [   " $ O S "   = =   " d e b i a n "   | |   " $ O S "   = =   " u b u n t u "   ] ] ;   t h e n 
         u n s e t   D E B I A N _ F R O N T E N D 
 f i 
 
 e c h o   " - - -   P r o c e s s u s   d ' i n s t a l l a t i o n   t e r m i n é   !   - - - " 
 e c h o   " V é r i f i e z   l e s   l o g s   d u   t u n n e l   S y s t e m d :   j o u r n a l c t l   - u   $ { S E R V I C E _ N A M E }   - n   1 0 0 " 
 e c h o   " S t a t u t   d u   c o n t e n e u r   D o c k e r :   d o c k e r   p s   - a   |   g r e p   v p s - a g e n t - c o n t a i n e r " 
