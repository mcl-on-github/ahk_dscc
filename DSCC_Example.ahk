#Include DSCC.ahk

DSCap := DShow.Capture()

deviceList := DShow.EnumerateDevices(DShow.CLSID_VideoInputDeviceCategory)
queryPrompt := ''
For index, device In deviceList
	queryPrompt .= Format('{}. {}`n', index, device)

queryResult := InputBox(queryPrompt, 'Select device',, 1)
If (queryResult.Result != 'OK')
	ExitApp

;  DSCap.SetCaptureDevice(1)                   ; Select first device
;  DSCap.SetCaptureDevice('USB Video Device')  ; Select device by name
DSCap.SetCaptureDevice( Integer(queryResult.Value) )  ; Get first video capture device
DSCap.StartCapture(True)
DSWin := WinWait("ahk_class VideoRenderer")

WinSetAlwaysOnTop(True, DSWin)

; Position preview window to right bottom corner
WinGetPos(&wx, &wy, &ww, &wh, DSWin)
WinGetPos(&tx, &ty, &tw, &th, "ahk_class Shell_TrayWnd")
WinMove( A_ScreenWidth - 400,  A_ScreenHeight - th - 300, 400, 300, DSWin )

Return


Esc::
{
	WinHide DSWin
	DSCap.StopCapture()
	ExitApp
}

F1::
{
	bufImage := DSCap.GrabFrame()
	If Not bufImage Is Buffer
		Return
	
	bufBmpHeader := Buffer(14+40, 0)  ; sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER)
	bmpDataSize  := bufImage.frameW * bufImage.frameH * 4
	NumPut(
	; BITMAPFILEHEADER
		  'UShort', 0x4D42             ; 'BM' signature
		, 'UInt'  , 14+40+bmpDataSize  ; File size
		, 'UInt'  , 0                  ; two reserved words
		, 'UInt'  , 14+40              ; Data offset
	; BITMAPINFOHEADER
		, 'UInt'  , 40               ; .biSize
		, 'UInt'  , bufImage.frameW  ; .biWidth
		, 'UInt'  , bufImage.frameH  ; .biHeight
		, 'UShort',  1               ; .biPlanes
		, 'UShort', 32               ; .biBitCount
	    , 'UInt'  ,  0               ; .biCompression
	    , 'UInt'  , bmpDataSize      ; .biSizeImage
	    , 'UInt'  , 0xEC3            ; .biXPelsPerMeter ~ 96 dpi
	    , 'UInt'  , 0xEC3            ; .biYPelsPerMeter ~ 96 dpi
	    , 'UInt'  , 0                ; .biClrUsed
	    , 'UInt'  , 0                ; .biClrImportant
	, bufBmpHeader)
	
	outFile := FileOpen(Format('Snap_{}.bmp', A_Now), 'w', 'CP0')
	; BITMAPFILEHEADER
	outFile.RawWrite(bufBmpHeader)
	outFile.RawWrite(bufImage)
	outFile.Close()
}