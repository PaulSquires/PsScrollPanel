'    CScrollPanel demo harness
'
'    This program is free software: you can redistribute it and/or modify
'    it under the terms of the GNU General Public License as published by
'    the Free Software Foundation, either version 3 of the License, or
'    (at your option) any later version.
'
'    This program is distributed in the hope that it will be useful,
'    but WITHOUT any WARRANTY; without even the implied warranty of
'    MERCHANTABILITY or FITNESS for A PARTICULAR PURPOSE.  See the
'    GNU General Public License for more details.

#pragma once


#define IDC_FRMMAIN_SCROLLPANEL   1000
#define IDC_FRMMAIN_TESTPANEL     1100   ' the self-test's own throwaway instance
#define IDC_FRMMAIN_FIRSTROW      2000   ' row control ids run upward from here

declare function frmMain_Show( byval hWndParent as HWND ) as LRESULT
