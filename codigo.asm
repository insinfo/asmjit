
.\codigo.bin:     file format binary


Disassembly of section .data:

0000000000000000 <.data>:
   0:	55                   	push   rbp
   1:	48 89 e5             	mov    rbp,rsp
   4:	48 83 ec 40          	sub    rsp,0x40
   8:	48 89 5d d8          	mov    QWORD PTR [rbp-0x28],rbx
   c:	48 89 75 d0          	mov    QWORD PTR [rbp-0x30],rsi
  10:	48 89 7d c8          	mov    QWORD PTR [rbp-0x38],rdi
  14:	48 89 cb             	mov    rbx,rcx
  17:	48 89 d6             	mov    rsi,rdx
  1a:	4d 89 c1             	mov    r9,r8
  1d:	4c 89 4d f8          	mov    QWORD PTR [rbp-0x8],r9
  21:	48 8b 45 f8          	mov    rax,QWORD PTR [rbp-0x8]
  25:	49 81 f9 40 00 00 00 	cmp    r9,0x40
  2c:	0f 82 00 00 00 00    	jb     0x32
  32:	48 8b 45 f8          	mov    rax,QWORD PTR [rbp-0x8]
  36:	f3 0f 6f 20          	movdqu xmm4,XMMWORD PTR [rax]
  3a:	f3 0f 6f 48 10       	movdqu xmm1,XMMWORD PTR [rax+0x10]
  3f:	f3 0f 6f 58 20       	movdqu xmm3,XMMWORD PTR [rax+0x20]
  44:	f3 0f 6f 50 30       	movdqu xmm2,XMMWORD PTR [rax+0x30]
  49:	66 0f fe e1          	paddd  xmm4,xmm1
  4d:	66 0f ef d4          	pxor   xmm2,xmm4
  51:	f3 0f 6f c2          	movdqu xmm0,xmm2
  55:	66 0f 72 f2 10       	pslld  xmm2,0x10
  5a:	66 0f 72 d0 10       	psrld  xmm0,0x10
  5f:	66 0f eb d0          	por    xmm2,xmm0
  63:	66 0f fe da          	paddd  xmm3,xmm2
  67:	66 0f ef cb          	pxor   xmm1,xmm3
  6b:	f3 0f 6f c1          	movdqu xmm0,xmm1
  6f:	66 0f 72 f1 0c       	pslld  xmm1,0xc
  74:	66 0f 72 d0 14       	psrld  xmm0,0x14
  79:	66 0f eb c8          	por    xmm1,xmm0
  7d:	66 0f fe e1          	paddd  xmm4,xmm1
  81:	66 0f ef d4          	pxor   xmm2,xmm4
  85:	f3 0f 6f c2          	movdqu xmm0,xmm2
  89:	66 0f 72 f2 08       	pslld  xmm2,0x8
  8e:	66 0f 72 d0 18       	psrld  xmm0,0x18
  93:	66 0f eb d0          	por    xmm2,xmm0
  97:	66 0f fe da          	paddd  xmm3,xmm2
  9b:	66 0f ef cb          	pxor   xmm1,xmm3
  9f:	f3 0f 6f c1          	movdqu xmm0,xmm1
  a3:	66 0f 72 f1 07       	pslld  xmm1,0x7
  a8:	66 0f 72 d0 19       	psrld  xmm0,0x19
  ad:	66 0f eb c8          	por    xmm1,xmm0
  b1:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
  b6:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
  bb:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
  c0:	66 0f fe e1          	paddd  xmm4,xmm1
  c4:	66 0f ef d4          	pxor   xmm2,xmm4
  c8:	f3 0f 6f c2          	movdqu xmm0,xmm2
  cc:	66 0f 72 f2 10       	pslld  xmm2,0x10
  d1:	66 0f 72 d0 10       	psrld  xmm0,0x10
  d6:	66 0f eb d0          	por    xmm2,xmm0
  da:	66 0f fe da          	paddd  xmm3,xmm2
  de:	66 0f ef cb          	pxor   xmm1,xmm3
  e2:	f3 0f 6f c1          	movdqu xmm0,xmm1
  e6:	66 0f 72 f1 0c       	pslld  xmm1,0xc
  eb:	66 0f 72 d0 14       	psrld  xmm0,0x14
  f0:	66 0f eb c8          	por    xmm1,xmm0
  f4:	66 0f fe e1          	paddd  xmm4,xmm1
  f8:	66 0f ef d4          	pxor   xmm2,xmm4
  fc:	f3 0f 6f c2          	movdqu xmm0,xmm2
 100:	66 0f 72 f2 08       	pslld  xmm2,0x8
 105:	66 0f 72 d0 18       	psrld  xmm0,0x18
 10a:	66 0f eb d0          	por    xmm2,xmm0
 10e:	66 0f fe da          	paddd  xmm3,xmm2
 112:	66 0f ef cb          	pxor   xmm1,xmm3
 116:	f3 0f 6f c1          	movdqu xmm0,xmm1
 11a:	66 0f 72 f1 07       	pslld  xmm1,0x7
 11f:	66 0f 72 d0 19       	psrld  xmm0,0x19
 124:	66 0f eb c8          	por    xmm1,xmm0
 128:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 12d:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 132:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 137:	66 0f fe e1          	paddd  xmm4,xmm1
 13b:	66 0f ef d4          	pxor   xmm2,xmm4
 13f:	f3 0f 6f c2          	movdqu xmm0,xmm2
 143:	66 0f 72 f2 10       	pslld  xmm2,0x10
 148:	66 0f 72 d0 10       	psrld  xmm0,0x10
 14d:	66 0f eb d0          	por    xmm2,xmm0
 151:	66 0f fe da          	paddd  xmm3,xmm2
 155:	66 0f ef cb          	pxor   xmm1,xmm3
 159:	f3 0f 6f c1          	movdqu xmm0,xmm1
 15d:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 162:	66 0f 72 d0 14       	psrld  xmm0,0x14
 167:	66 0f eb c8          	por    xmm1,xmm0
 16b:	66 0f fe e1          	paddd  xmm4,xmm1
 16f:	66 0f ef d4          	pxor   xmm2,xmm4
 173:	f3 0f 6f c2          	movdqu xmm0,xmm2
 177:	66 0f 72 f2 08       	pslld  xmm2,0x8
 17c:	66 0f 72 d0 18       	psrld  xmm0,0x18
 181:	66 0f eb d0          	por    xmm2,xmm0
 185:	66 0f fe da          	paddd  xmm3,xmm2
 189:	66 0f ef cb          	pxor   xmm1,xmm3
 18d:	f3 0f 6f c1          	movdqu xmm0,xmm1
 191:	66 0f 72 f1 07       	pslld  xmm1,0x7
 196:	66 0f 72 d0 19       	psrld  xmm0,0x19
 19b:	66 0f eb c8          	por    xmm1,xmm0
 19f:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 1a4:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 1a9:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 1ae:	66 0f fe e1          	paddd  xmm4,xmm1
 1b2:	66 0f ef d4          	pxor   xmm2,xmm4
 1b6:	f3 0f 6f c2          	movdqu xmm0,xmm2
 1ba:	66 0f 72 f2 10       	pslld  xmm2,0x10
 1bf:	66 0f 72 d0 10       	psrld  xmm0,0x10
 1c4:	66 0f eb d0          	por    xmm2,xmm0
 1c8:	66 0f fe da          	paddd  xmm3,xmm2
 1cc:	66 0f ef cb          	pxor   xmm1,xmm3
 1d0:	f3 0f 6f c1          	movdqu xmm0,xmm1
 1d4:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 1d9:	66 0f 72 d0 14       	psrld  xmm0,0x14
 1de:	66 0f eb c8          	por    xmm1,xmm0
 1e2:	66 0f fe e1          	paddd  xmm4,xmm1
 1e6:	66 0f ef d4          	pxor   xmm2,xmm4
 1ea:	f3 0f 6f c2          	movdqu xmm0,xmm2
 1ee:	66 0f 72 f2 08       	pslld  xmm2,0x8
 1f3:	66 0f 72 d0 18       	psrld  xmm0,0x18
 1f8:	66 0f eb d0          	por    xmm2,xmm0
 1fc:	66 0f fe da          	paddd  xmm3,xmm2
 200:	66 0f ef cb          	pxor   xmm1,xmm3
 204:	f3 0f 6f c1          	movdqu xmm0,xmm1
 208:	66 0f 72 f1 07       	pslld  xmm1,0x7
 20d:	66 0f 72 d0 19       	psrld  xmm0,0x19
 212:	66 0f eb c8          	por    xmm1,xmm0
 216:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 21b:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 220:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 225:	66 0f fe e1          	paddd  xmm4,xmm1
 229:	66 0f ef d4          	pxor   xmm2,xmm4
 22d:	f3 0f 6f c2          	movdqu xmm0,xmm2
 231:	66 0f 72 f2 10       	pslld  xmm2,0x10
 236:	66 0f 72 d0 10       	psrld  xmm0,0x10
 23b:	66 0f eb d0          	por    xmm2,xmm0
 23f:	66 0f fe da          	paddd  xmm3,xmm2
 243:	66 0f ef cb          	pxor   xmm1,xmm3
 247:	f3 0f 6f c1          	movdqu xmm0,xmm1
 24b:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 250:	66 0f 72 d0 14       	psrld  xmm0,0x14
 255:	66 0f eb c8          	por    xmm1,xmm0
 259:	66 0f fe e1          	paddd  xmm4,xmm1
 25d:	66 0f ef d4          	pxor   xmm2,xmm4
 261:	f3 0f 6f c2          	movdqu xmm0,xmm2
 265:	66 0f 72 f2 08       	pslld  xmm2,0x8
 26a:	66 0f 72 d0 18       	psrld  xmm0,0x18
 26f:	66 0f eb d0          	por    xmm2,xmm0
 273:	66 0f fe da          	paddd  xmm3,xmm2
 277:	66 0f ef cb          	pxor   xmm1,xmm3
 27b:	f3 0f 6f c1          	movdqu xmm0,xmm1
 27f:	66 0f 72 f1 07       	pslld  xmm1,0x7
 284:	66 0f 72 d0 19       	psrld  xmm0,0x19
 289:	66 0f eb c8          	por    xmm1,xmm0
 28d:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 292:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 297:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 29c:	66 0f fe e1          	paddd  xmm4,xmm1
 2a0:	66 0f ef d4          	pxor   xmm2,xmm4
 2a4:	f3 0f 6f c2          	movdqu xmm0,xmm2
 2a8:	66 0f 72 f2 10       	pslld  xmm2,0x10
 2ad:	66 0f 72 d0 10       	psrld  xmm0,0x10
 2b2:	66 0f eb d0          	por    xmm2,xmm0
 2b6:	66 0f fe da          	paddd  xmm3,xmm2
 2ba:	66 0f ef cb          	pxor   xmm1,xmm3
 2be:	f3 0f 6f c1          	movdqu xmm0,xmm1
 2c2:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 2c7:	66 0f 72 d0 14       	psrld  xmm0,0x14
 2cc:	66 0f eb c8          	por    xmm1,xmm0
 2d0:	66 0f fe e1          	paddd  xmm4,xmm1
 2d4:	66 0f ef d4          	pxor   xmm2,xmm4
 2d8:	f3 0f 6f c2          	movdqu xmm0,xmm2
 2dc:	66 0f 72 f2 08       	pslld  xmm2,0x8
 2e1:	66 0f 72 d0 18       	psrld  xmm0,0x18
 2e6:	66 0f eb d0          	por    xmm2,xmm0
 2ea:	66 0f fe da          	paddd  xmm3,xmm2
 2ee:	66 0f ef cb          	pxor   xmm1,xmm3
 2f2:	f3 0f 6f c1          	movdqu xmm0,xmm1
 2f6:	66 0f 72 f1 07       	pslld  xmm1,0x7
 2fb:	66 0f 72 d0 19       	psrld  xmm0,0x19
 300:	66 0f eb c8          	por    xmm1,xmm0
 304:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 309:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 30e:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 313:	66 0f fe e1          	paddd  xmm4,xmm1
 317:	66 0f ef d4          	pxor   xmm2,xmm4
 31b:	f3 0f 6f c2          	movdqu xmm0,xmm2
 31f:	66 0f 72 f2 10       	pslld  xmm2,0x10
 324:	66 0f 72 d0 10       	psrld  xmm0,0x10
 329:	66 0f eb d0          	por    xmm2,xmm0
 32d:	66 0f fe da          	paddd  xmm3,xmm2
 331:	66 0f ef cb          	pxor   xmm1,xmm3
 335:	f3 0f 6f c1          	movdqu xmm0,xmm1
 339:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 33e:	66 0f 72 d0 14       	psrld  xmm0,0x14
 343:	66 0f eb c8          	por    xmm1,xmm0
 347:	66 0f fe e1          	paddd  xmm4,xmm1
 34b:	66 0f ef d4          	pxor   xmm2,xmm4
 34f:	f3 0f 6f c2          	movdqu xmm0,xmm2
 353:	66 0f 72 f2 08       	pslld  xmm2,0x8
 358:	66 0f 72 d0 18       	psrld  xmm0,0x18
 35d:	66 0f eb d0          	por    xmm2,xmm0
 361:	66 0f fe da          	paddd  xmm3,xmm2
 365:	66 0f ef cb          	pxor   xmm1,xmm3
 369:	f3 0f 6f c1          	movdqu xmm0,xmm1
 36d:	66 0f 72 f1 07       	pslld  xmm1,0x7
 372:	66 0f 72 d0 19       	psrld  xmm0,0x19
 377:	66 0f eb c8          	por    xmm1,xmm0
 37b:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 380:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 385:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 38a:	66 0f fe e1          	paddd  xmm4,xmm1
 38e:	66 0f ef d4          	pxor   xmm2,xmm4
 392:	f3 0f 6f c2          	movdqu xmm0,xmm2
 396:	66 0f 72 f2 10       	pslld  xmm2,0x10
 39b:	66 0f 72 d0 10       	psrld  xmm0,0x10
 3a0:	66 0f eb d0          	por    xmm2,xmm0
 3a4:	66 0f fe da          	paddd  xmm3,xmm2
 3a8:	66 0f ef cb          	pxor   xmm1,xmm3
 3ac:	f3 0f 6f c1          	movdqu xmm0,xmm1
 3b0:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 3b5:	66 0f 72 d0 14       	psrld  xmm0,0x14
 3ba:	66 0f eb c8          	por    xmm1,xmm0
 3be:	66 0f fe e1          	paddd  xmm4,xmm1
 3c2:	66 0f ef d4          	pxor   xmm2,xmm4
 3c6:	f3 0f 6f c2          	movdqu xmm0,xmm2
 3ca:	66 0f 72 f2 08       	pslld  xmm2,0x8
 3cf:	66 0f 72 d0 18       	psrld  xmm0,0x18
 3d4:	66 0f eb d0          	por    xmm2,xmm0
 3d8:	66 0f fe da          	paddd  xmm3,xmm2
 3dc:	66 0f ef cb          	pxor   xmm1,xmm3
 3e0:	f3 0f 6f c1          	movdqu xmm0,xmm1
 3e4:	66 0f 72 f1 07       	pslld  xmm1,0x7
 3e9:	66 0f 72 d0 19       	psrld  xmm0,0x19
 3ee:	66 0f eb c8          	por    xmm1,xmm0
 3f2:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 3f7:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 3fc:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 401:	66 0f fe e1          	paddd  xmm4,xmm1
 405:	66 0f ef d4          	pxor   xmm2,xmm4
 409:	f3 0f 6f c2          	movdqu xmm0,xmm2
 40d:	66 0f 72 f2 10       	pslld  xmm2,0x10
 412:	66 0f 72 d0 10       	psrld  xmm0,0x10
 417:	66 0f eb d0          	por    xmm2,xmm0
 41b:	66 0f fe da          	paddd  xmm3,xmm2
 41f:	66 0f ef cb          	pxor   xmm1,xmm3
 423:	f3 0f 6f c1          	movdqu xmm0,xmm1
 427:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 42c:	66 0f 72 d0 14       	psrld  xmm0,0x14
 431:	66 0f eb c8          	por    xmm1,xmm0
 435:	66 0f fe e1          	paddd  xmm4,xmm1
 439:	66 0f ef d4          	pxor   xmm2,xmm4
 43d:	f3 0f 6f c2          	movdqu xmm0,xmm2
 441:	66 0f 72 f2 08       	pslld  xmm2,0x8
 446:	66 0f 72 d0 18       	psrld  xmm0,0x18
 44b:	66 0f eb d0          	por    xmm2,xmm0
 44f:	66 0f fe da          	paddd  xmm3,xmm2
 453:	66 0f ef cb          	pxor   xmm1,xmm3
 457:	f3 0f 6f c1          	movdqu xmm0,xmm1
 45b:	66 0f 72 f1 07       	pslld  xmm1,0x7
 460:	66 0f 72 d0 19       	psrld  xmm0,0x19
 465:	66 0f eb c8          	por    xmm1,xmm0
 469:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 46e:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 473:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 478:	66 0f fe e1          	paddd  xmm4,xmm1
 47c:	66 0f ef d4          	pxor   xmm2,xmm4
 480:	f3 0f 6f c2          	movdqu xmm0,xmm2
 484:	66 0f 72 f2 10       	pslld  xmm2,0x10
 489:	66 0f 72 d0 10       	psrld  xmm0,0x10
 48e:	66 0f eb d0          	por    xmm2,xmm0
 492:	66 0f fe da          	paddd  xmm3,xmm2
 496:	66 0f ef cb          	pxor   xmm1,xmm3
 49a:	f3 0f 6f c1          	movdqu xmm0,xmm1
 49e:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 4a3:	66 0f 72 d0 14       	psrld  xmm0,0x14
 4a8:	66 0f eb c8          	por    xmm1,xmm0
 4ac:	66 0f fe e1          	paddd  xmm4,xmm1
 4b0:	66 0f ef d4          	pxor   xmm2,xmm4
 4b4:	f3 0f 6f c2          	movdqu xmm0,xmm2
 4b8:	66 0f 72 f2 08       	pslld  xmm2,0x8
 4bd:	66 0f 72 d0 18       	psrld  xmm0,0x18
 4c2:	66 0f eb d0          	por    xmm2,xmm0
 4c6:	66 0f fe da          	paddd  xmm3,xmm2
 4ca:	66 0f ef cb          	pxor   xmm1,xmm3
 4ce:	f3 0f 6f c1          	movdqu xmm0,xmm1
 4d2:	66 0f 72 f1 07       	pslld  xmm1,0x7
 4d7:	66 0f 72 d0 19       	psrld  xmm0,0x19
 4dc:	66 0f eb c8          	por    xmm1,xmm0
 4e0:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 4e5:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 4ea:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 4ef:	66 0f fe e1          	paddd  xmm4,xmm1
 4f3:	66 0f ef d4          	pxor   xmm2,xmm4
 4f7:	f3 0f 6f c2          	movdqu xmm0,xmm2
 4fb:	66 0f 72 f2 10       	pslld  xmm2,0x10
 500:	66 0f 72 d0 10       	psrld  xmm0,0x10
 505:	66 0f eb d0          	por    xmm2,xmm0
 509:	66 0f fe da          	paddd  xmm3,xmm2
 50d:	66 0f ef cb          	pxor   xmm1,xmm3
 511:	f3 0f 6f c1          	movdqu xmm0,xmm1
 515:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 51a:	66 0f 72 d0 14       	psrld  xmm0,0x14
 51f:	66 0f eb c8          	por    xmm1,xmm0
 523:	66 0f fe e1          	paddd  xmm4,xmm1
 527:	66 0f ef d4          	pxor   xmm2,xmm4
 52b:	f3 0f 6f c2          	movdqu xmm0,xmm2
 52f:	66 0f 72 f2 08       	pslld  xmm2,0x8
 534:	66 0f 72 d0 18       	psrld  xmm0,0x18
 539:	66 0f eb d0          	por    xmm2,xmm0
 53d:	66 0f fe da          	paddd  xmm3,xmm2
 541:	66 0f ef cb          	pxor   xmm1,xmm3
 545:	f3 0f 6f c1          	movdqu xmm0,xmm1
 549:	66 0f 72 f1 07       	pslld  xmm1,0x7
 54e:	66 0f 72 d0 19       	psrld  xmm0,0x19
 553:	66 0f eb c8          	por    xmm1,xmm0
 557:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 55c:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 561:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 566:	66 0f fe e1          	paddd  xmm4,xmm1
 56a:	66 0f ef d4          	pxor   xmm2,xmm4
 56e:	f3 0f 6f c2          	movdqu xmm0,xmm2
 572:	66 0f 72 f2 10       	pslld  xmm2,0x10
 577:	66 0f 72 d0 10       	psrld  xmm0,0x10
 57c:	66 0f eb d0          	por    xmm2,xmm0
 580:	66 0f fe da          	paddd  xmm3,xmm2
 584:	66 0f ef cb          	pxor   xmm1,xmm3
 588:	f3 0f 6f c1          	movdqu xmm0,xmm1
 58c:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 591:	66 0f 72 d0 14       	psrld  xmm0,0x14
 596:	66 0f eb c8          	por    xmm1,xmm0
 59a:	66 0f fe e1          	paddd  xmm4,xmm1
 59e:	66 0f ef d4          	pxor   xmm2,xmm4
 5a2:	f3 0f 6f c2          	movdqu xmm0,xmm2
 5a6:	66 0f 72 f2 08       	pslld  xmm2,0x8
 5ab:	66 0f 72 d0 18       	psrld  xmm0,0x18
 5b0:	66 0f eb d0          	por    xmm2,xmm0
 5b4:	66 0f fe da          	paddd  xmm3,xmm2
 5b8:	66 0f ef cb          	pxor   xmm1,xmm3
 5bc:	f3 0f 6f c1          	movdqu xmm0,xmm1
 5c0:	66 0f 72 f1 07       	pslld  xmm1,0x7
 5c5:	66 0f 72 d0 19       	psrld  xmm0,0x19
 5ca:	66 0f eb c8          	por    xmm1,xmm0
 5ce:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 5d3:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 5d8:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 5dd:	66 0f fe e1          	paddd  xmm4,xmm1
 5e1:	66 0f ef d4          	pxor   xmm2,xmm4
 5e5:	f3 0f 6f c2          	movdqu xmm0,xmm2
 5e9:	66 0f 72 f2 10       	pslld  xmm2,0x10
 5ee:	66 0f 72 d0 10       	psrld  xmm0,0x10
 5f3:	66 0f eb d0          	por    xmm2,xmm0
 5f7:	66 0f fe da          	paddd  xmm3,xmm2
 5fb:	66 0f ef cb          	pxor   xmm1,xmm3
 5ff:	f3 0f 6f c1          	movdqu xmm0,xmm1
 603:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 608:	66 0f 72 d0 14       	psrld  xmm0,0x14
 60d:	66 0f eb c8          	por    xmm1,xmm0
 611:	66 0f fe e1          	paddd  xmm4,xmm1
 615:	66 0f ef d4          	pxor   xmm2,xmm4
 619:	f3 0f 6f c2          	movdqu xmm0,xmm2
 61d:	66 0f 72 f2 08       	pslld  xmm2,0x8
 622:	66 0f 72 d0 18       	psrld  xmm0,0x18
 627:	66 0f eb d0          	por    xmm2,xmm0
 62b:	66 0f fe da          	paddd  xmm3,xmm2
 62f:	66 0f ef cb          	pxor   xmm1,xmm3
 633:	f3 0f 6f c1          	movdqu xmm0,xmm1
 637:	66 0f 72 f1 07       	pslld  xmm1,0x7
 63c:	66 0f 72 d0 19       	psrld  xmm0,0x19
 641:	66 0f eb c8          	por    xmm1,xmm0
 645:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 64a:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 64f:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 654:	66 0f fe e1          	paddd  xmm4,xmm1
 658:	66 0f ef d4          	pxor   xmm2,xmm4
 65c:	f3 0f 6f c2          	movdqu xmm0,xmm2
 660:	66 0f 72 f2 10       	pslld  xmm2,0x10
 665:	66 0f 72 d0 10       	psrld  xmm0,0x10
 66a:	66 0f eb d0          	por    xmm2,xmm0
 66e:	66 0f fe da          	paddd  xmm3,xmm2
 672:	66 0f ef cb          	pxor   xmm1,xmm3
 676:	f3 0f 6f c1          	movdqu xmm0,xmm1
 67a:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 67f:	66 0f 72 d0 14       	psrld  xmm0,0x14
 684:	66 0f eb c8          	por    xmm1,xmm0
 688:	66 0f fe e1          	paddd  xmm4,xmm1
 68c:	66 0f ef d4          	pxor   xmm2,xmm4
 690:	f3 0f 6f c2          	movdqu xmm0,xmm2
 694:	66 0f 72 f2 08       	pslld  xmm2,0x8
 699:	66 0f 72 d0 18       	psrld  xmm0,0x18
 69e:	66 0f eb d0          	por    xmm2,xmm0
 6a2:	66 0f fe da          	paddd  xmm3,xmm2
 6a6:	66 0f ef cb          	pxor   xmm1,xmm3
 6aa:	f3 0f 6f c1          	movdqu xmm0,xmm1
 6ae:	66 0f 72 f1 07       	pslld  xmm1,0x7
 6b3:	66 0f 72 d0 19       	psrld  xmm0,0x19
 6b8:	66 0f eb c8          	por    xmm1,xmm0
 6bc:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 6c1:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 6c6:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 6cb:	66 0f fe e1          	paddd  xmm4,xmm1
 6cf:	66 0f ef d4          	pxor   xmm2,xmm4
 6d3:	f3 0f 6f c2          	movdqu xmm0,xmm2
 6d7:	66 0f 72 f2 10       	pslld  xmm2,0x10
 6dc:	66 0f 72 d0 10       	psrld  xmm0,0x10
 6e1:	66 0f eb d0          	por    xmm2,xmm0
 6e5:	66 0f fe da          	paddd  xmm3,xmm2
 6e9:	66 0f ef cb          	pxor   xmm1,xmm3
 6ed:	f3 0f 6f c1          	movdqu xmm0,xmm1
 6f1:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 6f6:	66 0f 72 d0 14       	psrld  xmm0,0x14
 6fb:	66 0f eb c8          	por    xmm1,xmm0
 6ff:	66 0f fe e1          	paddd  xmm4,xmm1
 703:	66 0f ef d4          	pxor   xmm2,xmm4
 707:	f3 0f 6f c2          	movdqu xmm0,xmm2
 70b:	66 0f 72 f2 08       	pslld  xmm2,0x8
 710:	66 0f 72 d0 18       	psrld  xmm0,0x18
 715:	66 0f eb d0          	por    xmm2,xmm0
 719:	66 0f fe da          	paddd  xmm3,xmm2
 71d:	66 0f ef cb          	pxor   xmm1,xmm3
 721:	f3 0f 6f c1          	movdqu xmm0,xmm1
 725:	66 0f 72 f1 07       	pslld  xmm1,0x7
 72a:	66 0f 72 d0 19       	psrld  xmm0,0x19
 72f:	66 0f eb c8          	por    xmm1,xmm0
 733:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 738:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 73d:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 742:	66 0f fe e1          	paddd  xmm4,xmm1
 746:	66 0f ef d4          	pxor   xmm2,xmm4
 74a:	f3 0f 6f c2          	movdqu xmm0,xmm2
 74e:	66 0f 72 f2 10       	pslld  xmm2,0x10
 753:	66 0f 72 d0 10       	psrld  xmm0,0x10
 758:	66 0f eb d0          	por    xmm2,xmm0
 75c:	66 0f fe da          	paddd  xmm3,xmm2
 760:	66 0f ef cb          	pxor   xmm1,xmm3
 764:	f3 0f 6f c1          	movdqu xmm0,xmm1
 768:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 76d:	66 0f 72 d0 14       	psrld  xmm0,0x14
 772:	66 0f eb c8          	por    xmm1,xmm0
 776:	66 0f fe e1          	paddd  xmm4,xmm1
 77a:	66 0f ef d4          	pxor   xmm2,xmm4
 77e:	f3 0f 6f c2          	movdqu xmm0,xmm2
 782:	66 0f 72 f2 08       	pslld  xmm2,0x8
 787:	66 0f 72 d0 18       	psrld  xmm0,0x18
 78c:	66 0f eb d0          	por    xmm2,xmm0
 790:	66 0f fe da          	paddd  xmm3,xmm2
 794:	66 0f ef cb          	pxor   xmm1,xmm3
 798:	f3 0f 6f c1          	movdqu xmm0,xmm1
 79c:	66 0f 72 f1 07       	pslld  xmm1,0x7
 7a1:	66 0f 72 d0 19       	psrld  xmm0,0x19
 7a6:	66 0f eb c8          	por    xmm1,xmm0
 7aa:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 7af:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 7b4:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 7b9:	66 0f fe e1          	paddd  xmm4,xmm1
 7bd:	66 0f ef d4          	pxor   xmm2,xmm4
 7c1:	f3 0f 6f c2          	movdqu xmm0,xmm2
 7c5:	66 0f 72 f2 10       	pslld  xmm2,0x10
 7ca:	66 0f 72 d0 10       	psrld  xmm0,0x10
 7cf:	66 0f eb d0          	por    xmm2,xmm0
 7d3:	66 0f fe da          	paddd  xmm3,xmm2
 7d7:	66 0f ef cb          	pxor   xmm1,xmm3
 7db:	f3 0f 6f c1          	movdqu xmm0,xmm1
 7df:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 7e4:	66 0f 72 d0 14       	psrld  xmm0,0x14
 7e9:	66 0f eb c8          	por    xmm1,xmm0
 7ed:	66 0f fe e1          	paddd  xmm4,xmm1
 7f1:	66 0f ef d4          	pxor   xmm2,xmm4
 7f5:	f3 0f 6f c2          	movdqu xmm0,xmm2
 7f9:	66 0f 72 f2 08       	pslld  xmm2,0x8
 7fe:	66 0f 72 d0 18       	psrld  xmm0,0x18
 803:	66 0f eb d0          	por    xmm2,xmm0
 807:	66 0f fe da          	paddd  xmm3,xmm2
 80b:	66 0f ef cb          	pxor   xmm1,xmm3
 80f:	f3 0f 6f c1          	movdqu xmm0,xmm1
 813:	66 0f 72 f1 07       	pslld  xmm1,0x7
 818:	66 0f 72 d0 19       	psrld  xmm0,0x19
 81d:	66 0f eb c8          	por    xmm1,xmm0
 821:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 826:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 82b:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 830:	66 0f fe e1          	paddd  xmm4,xmm1
 834:	66 0f ef d4          	pxor   xmm2,xmm4
 838:	f3 0f 6f c2          	movdqu xmm0,xmm2
 83c:	66 0f 72 f2 10       	pslld  xmm2,0x10
 841:	66 0f 72 d0 10       	psrld  xmm0,0x10
 846:	66 0f eb d0          	por    xmm2,xmm0
 84a:	66 0f fe da          	paddd  xmm3,xmm2
 84e:	66 0f ef cb          	pxor   xmm1,xmm3
 852:	f3 0f 6f c1          	movdqu xmm0,xmm1
 856:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 85b:	66 0f 72 d0 14       	psrld  xmm0,0x14
 860:	66 0f eb c8          	por    xmm1,xmm0
 864:	66 0f fe e1          	paddd  xmm4,xmm1
 868:	66 0f ef d4          	pxor   xmm2,xmm4
 86c:	f3 0f 6f c2          	movdqu xmm0,xmm2
 870:	66 0f 72 f2 08       	pslld  xmm2,0x8
 875:	66 0f 72 d0 18       	psrld  xmm0,0x18
 87a:	66 0f eb d0          	por    xmm2,xmm0
 87e:	66 0f fe da          	paddd  xmm3,xmm2
 882:	66 0f ef cb          	pxor   xmm1,xmm3
 886:	f3 0f 6f c1          	movdqu xmm0,xmm1
 88a:	66 0f 72 f1 07       	pslld  xmm1,0x7
 88f:	66 0f 72 d0 19       	psrld  xmm0,0x19
 894:	66 0f eb c8          	por    xmm1,xmm0
 898:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 89d:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 8a2:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 8a7:	66 0f fe e1          	paddd  xmm4,xmm1
 8ab:	66 0f ef d4          	pxor   xmm2,xmm4
 8af:	f3 0f 6f c2          	movdqu xmm0,xmm2
 8b3:	66 0f 72 f2 10       	pslld  xmm2,0x10
 8b8:	66 0f 72 d0 10       	psrld  xmm0,0x10
 8bd:	66 0f eb d0          	por    xmm2,xmm0
 8c1:	66 0f fe da          	paddd  xmm3,xmm2
 8c5:	66 0f ef cb          	pxor   xmm1,xmm3
 8c9:	f3 0f 6f c1          	movdqu xmm0,xmm1
 8cd:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 8d2:	66 0f 72 d0 14       	psrld  xmm0,0x14
 8d7:	66 0f eb c8          	por    xmm1,xmm0
 8db:	66 0f fe e1          	paddd  xmm4,xmm1
 8df:	66 0f ef d4          	pxor   xmm2,xmm4
 8e3:	f3 0f 6f c2          	movdqu xmm0,xmm2
 8e7:	66 0f 72 f2 08       	pslld  xmm2,0x8
 8ec:	66 0f 72 d0 18       	psrld  xmm0,0x18
 8f1:	66 0f eb d0          	por    xmm2,xmm0
 8f5:	66 0f fe da          	paddd  xmm3,xmm2
 8f9:	66 0f ef cb          	pxor   xmm1,xmm3
 8fd:	f3 0f 6f c1          	movdqu xmm0,xmm1
 901:	66 0f 72 f1 07       	pslld  xmm1,0x7
 906:	66 0f 72 d0 19       	psrld  xmm0,0x19
 90b:	66 0f eb c8          	por    xmm1,xmm0
 90f:	66 0f 70 c9 39       	pshufd xmm1,xmm1,0x39
 914:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 919:	66 0f 70 d2 93       	pshufd xmm2,xmm2,0x93
 91e:	66 0f fe e1          	paddd  xmm4,xmm1
 922:	66 0f ef d4          	pxor   xmm2,xmm4
 926:	f3 0f 6f c2          	movdqu xmm0,xmm2
 92a:	66 0f 72 f2 10       	pslld  xmm2,0x10
 92f:	66 0f 72 d0 10       	psrld  xmm0,0x10
 934:	66 0f eb d0          	por    xmm2,xmm0
 938:	66 0f fe da          	paddd  xmm3,xmm2
 93c:	66 0f ef cb          	pxor   xmm1,xmm3
 940:	f3 0f 6f c1          	movdqu xmm0,xmm1
 944:	66 0f 72 f1 0c       	pslld  xmm1,0xc
 949:	66 0f 72 d0 14       	psrld  xmm0,0x14
 94e:	66 0f eb c8          	por    xmm1,xmm0
 952:	66 0f fe e1          	paddd  xmm4,xmm1
 956:	66 0f ef d4          	pxor   xmm2,xmm4
 95a:	f3 0f 6f c2          	movdqu xmm0,xmm2
 95e:	66 0f 72 f2 08       	pslld  xmm2,0x8
 963:	66 0f 72 d0 18       	psrld  xmm0,0x18
 968:	66 0f eb d0          	por    xmm2,xmm0
 96c:	66 0f fe da          	paddd  xmm3,xmm2
 970:	66 0f ef cb          	pxor   xmm1,xmm3
 974:	f3 0f 6f c1          	movdqu xmm0,xmm1
 978:	66 0f 72 f1 07       	pslld  xmm1,0x7
 97d:	66 0f 72 d0 19       	psrld  xmm0,0x19
 982:	66 0f eb c8          	por    xmm1,xmm0
 986:	66 0f 70 c9 93       	pshufd xmm1,xmm1,0x93
 98b:	66 0f 70 db 4e       	pshufd xmm3,xmm3,0x4e
 990:	66 0f 70 d2 39       	pshufd xmm2,xmm2,0x39
 995:	48 8b 45 f8          	mov    rax,QWORD PTR [rbp-0x8]
 999:	f3 0f 6f 00          	movdqu xmm0,XMMWORD PTR [rax]
 99d:	66 0f fe e0          	paddd  xmm4,xmm0
 9a1:	f3 0f 6f 40 10       	movdqu xmm0,XMMWORD PTR [rax+0x10]
 9a6:	66 0f fe c8          	paddd  xmm1,xmm0
 9aa:	f3 0f 6f 40 20       	movdqu xmm0,XMMWORD PTR [rax+0x20]
 9af:	66 0f fe d8          	paddd  xmm3,xmm0
 9b3:	f3 0f 6f 40 30       	movdqu xmm0,XMMWORD PTR [rax+0x30]
 9b8:	66 0f fe d0          	paddd  xmm2,xmm0
 9bc:	f3 0f 6f 06          	movdqu xmm0,XMMWORD PTR [rsi]
 9c0:	66 0f ef e0          	pxor   xmm4,xmm0
 9c4:	f3 0f 7f 23          	movdqu XMMWORD PTR [rbx],xmm4
 9c8:	f3 0f 6f 46 10       	movdqu xmm0,XMMWORD PTR [rsi+0x10]
 9cd:	66 0f ef c8          	pxor   xmm1,xmm0
 9d1:	f3 0f 7f 4b 10       	movdqu XMMWORD PTR [rbx+0x10],xmm1
 9d6:	f3 0f 6f 46 20       	movdqu xmm0,XMMWORD PTR [rsi+0x20]
 9db:	66 0f ef d8          	pxor   xmm3,xmm0
 9df:	f3 0f 7f 5b 20       	movdqu XMMWORD PTR [rbx+0x20],xmm3
 9e4:	f3 0f 6f 46 30       	movdqu xmm0,XMMWORD PTR [rsi+0x30]
 9e9:	66 0f ef d0          	pxor   xmm2,xmm0
 9ed:	f3 0f 7f 53 30       	movdqu XMMWORD PTR [rbx+0x30],xmm2
 9f2:	48 8b 45 f8          	mov    rax,QWORD PTR [rbp-0x8]
 9f6:	8b 48 30             	mov    ecx,DWORD PTR [rax+0x30]
 9f9:	83 c1 01             	add    ecx,0x1
 9fc:	48 8b 45 f8          	mov    rax,QWORD PTR [rbp-0x8]
 a00:	89 48 30             	mov    DWORD PTR [rax+0x30],ecx
 a03:	48 83 c6 40          	add    rsi,0x40
 a07:	48 83 c3 40          	add    rbx,0x40
 a0b:	49 83 c1 c0          	add    r9,0xffffffffffffffc0
 a0f:	49 81 f9 40 00 00 00 	cmp    r9,0x40
 a16:	0f 83 16 f6 ff ff    	jae    0x32
 a1c:	48 8b 5d f0          	mov    rbx,QWORD PTR [rbp-0x10]
 a20:	48 8b 75 e8          	mov    rsi,QWORD PTR [rbp-0x18]
 a24:	4c 8b 4d e0          	mov    r9,QWORD PTR [rbp-0x20]
 a28:	48 8b 7d f8          	mov    rdi,QWORD PTR [rbp-0x8]
 a2c:	48 8b 5d f0          	mov    rbx,QWORD PTR [rbp-0x10]
 a30:	48 8b 75 e8          	mov    rsi,QWORD PTR [rbp-0x18]
 a34:	4c 8b 4d e0          	mov    r9,QWORD PTR [rbp-0x20]
 a38:	48 8b 7d f8          	mov    rdi,QWORD PTR [rbp-0x8]
 a3c:	48 8b 7d c8          	mov    rdi,QWORD PTR [rbp-0x38]
 a40:	48 8b 75 d0          	mov    rsi,QWORD PTR [rbp-0x30]
 a44:	48 8b 5d d8          	mov    rbx,QWORD PTR [rbp-0x28]
 a48:	48 89 ec             	mov    rsp,rbp
 a4b:	5d                   	pop    rbp
 a4c:	c3                   	ret
