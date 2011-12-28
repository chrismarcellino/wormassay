JSEG image segmentation program 

File "segdist" is the binary executable for image segmentation.
It is compiled on SGI IRIX 6.3, Sun Solaris 2.4, or Windows 95 operating systems.

For information on the algorithm, please read the following web document:
http://maya.ece.ucsb.edu/JSEG

PC Windows: The programs are built to "Console Application" using visual C.
            You can use dosprompt to run the program and specify the
            command line arguments.

To run the program, type "segdist" to show a list of command line arguments.

Example:

segdist -i test.rgb -t 2 -o test.seg.rgb 0.9 -s 128 192 -r9 test.map.gif 

If you have any questions, please contact the authors. However,
we apologize that we are unable to reply every question due to limited 
time and resource.


----------------------------------------------------------

Copyright (C) 1999, 
The Regents of the University of California,
Samsung Electronics Corporation.
All rights reserved.
6/19/99

Author: Yining Deng and B.S. Manjunath

THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO
EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, INDIRECT OR
CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.


