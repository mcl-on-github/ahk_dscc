#Requires AutoHotkey v2.0

#Include DSCC.ahk
#Include Tesseract.ahk

; 1. Download Tesseract 5.5 installer from https://github.com/UB-Mannheim/tesseract/wiki
; 2. Unpack it into %A_ScriptDir%\Tesseract
; 3. Download trained language data from https://github.com/tesseract-ocr/tessdata
; 4. Put it into %A_ScriptDir%\Tesseract\tessdata
; 5. Run it.

Tess := Tesseract()

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
	Static useLeptonica := False
	
	bufImage := DSCap.GrabFrame()
	If Not bufImage Is Buffer
		Return
	
	If (useLeptonica) {
		bufImage := Tess.LeptonizeImage(bufImage)
		Tess.SetImage(bufImage, bufImage.frameW, bufImage.frameH, Floor(bufImage.bytesPerLine / bufImage.frameW), bufImage.bytesPerLine)
		
	} Else {
		; Image data in the buffer is upside-down. Flip manually
		bufFlipped := Buffer(bufImage.Size)
		bytesPerLine := bufImage.frameW * 4
		
		Loop bufImage.frameH {
			srcPtr := bufImage.Ptr + (A_Index-1) * bytesPerLine
			dstPtr := bufFlipped.Ptr    + bufImage.Size - A_Index * bytesPerLine
			DllCall("msvcrt\memcpy", "Ptr", dstPtr, "Ptr", srcPtr, "Ptr", bytesPerLine)
		}
		
		For propName In bufImage.OwnProps() {
			bufFlipped.DefineProp(propName, bufImage.GetOwnPropDesc(propName))
		}
		
		Tess.SetImage(bufFlipped, bufFlipped.frameW, bufImage.frameH, 4, bytesPerLine)
	}
	MsgBox Tess.GetText()
}