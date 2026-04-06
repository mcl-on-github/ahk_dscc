#Requires AutoHotkey v2.0

#DllLoad "*i %A_ScriptDir%\Tesseract\libtesseract-5.dll"


Class Tesseract {
	libt     := "libtesseract-5.dll"
	root     := A_ScriptDir . "\Tesseract"
	datapath := A_ScriptDir . "\Tesseract\tessdata"
	
	
	__New(language := "eng") {
		this.tessHandle := DllCall(this.libt . "\TessBaseAPICreate",  "Ptr")
		If (this.tessHandle == 0)
			Throw Error("Unable to create TessBaseAPI instance", -1)
		
		If (0 != DllCall(this.libt . "\TessBaseAPIInit3"
			, "Ptr" , this.tessHandle
			, "AStr", this.datapath
			, "AStr", language
			, "Int"
		))
			Throw Error("Unable to init TessBaseAPI", -1)
	}
	
	__Delete() {
		DllCall(this.libt . "\TessBaseAPIDelete",  "Ptr", this.tessHandle)
	}
	
	
	SetVariable(varName, varValue) {
		DllCall(this.libt . "\TessBaseAPISetVariable",  "Ptr", this.tessHandle,  "AStr", varName,  "AStr", varValue)
	}
	
	
	SetPageSegMode(mode) {
		DllCall(this.libt . "\TessBaseAPISetPageSegMode",  "Ptr", this.tessHandle,  "Int", mode)
	}
	
	
	SetImage(bufImage, frameW, frameH, bytesPerPixel := 4, bytesPerLine?) {
		bytesPerLine := bytesPerLine ?? ((frameW * bytesPerPixel + 3) & 0xFFFC)
		DllCall(this.libt . "\TessBaseAPISetImage"
			, "Ptr", this.tessHandle
			, "Ptr", bufImage
			, "Int", frameW
			, "Int", frameH
			, "Int", bytesPerPixel
			, "Int", bytesPerLine
		)
	}
	
	
	GetText(type := "") {
		Switch type, 0 {
			Case "hocr"    : funcName := "TessBaseAPIGetHOCRText"
			Case "alto"    : funcName := "TessBaseAPIGetAltoText"
			Case "page"    : funcName := "TessBaseAPIGetPAGEText"
			Case "tsv"     : funcName := "TessBaseAPIGetTsvText"
			Case "boxtext" : funcName := "TessBaseAPIGetBoxText"
			Case "wordbox" : funcName := "TessBaseAPIGetWordStrBoxText"
			Case "lstmbox" : funcName := "TessBaseAPIGetLSTMBoxText"
			Default        : funcName := "TessBaseAPIGetUTF8Text"
		}
		
		If (funcName == "TessBaseAPIGetUTF8Text")
			textPtr := DllCall(this.libt . "\TessBaseAPIGetUTF8Text",  "Ptr", this.tessHandle)
		Else
			textPtr := DllCall(this.libt . "\" . funcName,  "Ptr", this.tessHandle,  "Int", 0)
		
		Return StrGet(textPtr, "UTF-8")
	}
	
	
	GetVersion() {
		versionStr := DllCall(this.libt . "\TessVersion", "AStr")
	}
	
	
	
	;  Modifies raw image using libLeptonica for quicker and better recognition
	
	LeptonizeImage(bufImage) {
		bufImage.leptonized := False
		bufImage.bytesPerLine := bufImage.frameW * 4
		
		lPix := DllCall("libleptonica-6.dll\pixCreateHeader", "Int", bufImage.frameW, "Int", bufImage.frameH, "Int", 32)
		If Not lPix
			Return bufImage
		
		DllCall("libleptonica-6.dll\pixSetData", "Ptr", lPix, "Ptr", bufImage)
		
		; Scale down twice and convert to gray
		lPix2 := DllCall("libleptonica-6.dll\pixScaleRGBToGray2",  "Ptr", lPix, "Float", 0.2126, "Float", 0.7152, "Float", 0.0722)
		DllCall("libleptonica-6.dll\pixSetData", "Ptr", lPix, "Ptr", 0)  ; Remember not to free our buffer
		DllCall("libleptonica-6.dll\pixDestroy", "Ptr*", &lPix)
		
		If Not lPix2
			Return bufImage
		
		; Flip image vertically
		bufMatrix := Buffer(4*6)
		NumPut(
			"Float", 1, "Float",   0, "Float", 0,
			"Float", 0, "Float",  -1, "Float", NumGet(lPix2,  4, "Int"),  ; lPix2.height
			bufMatrix
		)
		
		lPix3 := DllCall("libleptonica-6.dll\pixAffine", "Ptr", lPix2, "Ptr", bufMatrix, "Int", 0)
		DllCall("libleptonica-6.dll\pixDestroy", "Ptr*", &lPix2)
		
		If Not lPix3
			Return bufImage
		
		; DllCall("libleptonica-6.dll\pixWrite", "AStr", Format("DEBUG_{}_3.jpg", A_TickCount), "Ptr", lPix3, "Int", 2)

		; Remove shadows etc by normalizing background
		tileX := 16, tileY := 16, tileR := 11/16, tileS := 8
		lPix4 := DllCall("libleptonica-6.dll\pixBackgroundNorm", "Ptr", lPix3
		, "Ptr", 0, "Ptr", 0
		, "Int", tileX, "Int", tileY   ; Tile size
		, "Int", 40, "Int", tileX*tileY*tileR, "Int", 200
		, "Int", tileS, "Int", tileS)  ; X/Y smooth
		DllCall("libleptonica-6.dll\pixDestroy", "Ptr*", &lPix3)
		
		If Not lPix4
			Return bufImage
		
		; Enhance by overlaying image on itself
		; This happens in-place
		; DllCall("libleptonica-6.dll\pixBlendHardLight"
		; 	, "Ptr", lPix4
		; 	, "Ptr", lPix4
		; 	, "Ptr", lPix4
		; 	, "Int", 0
		; 	, "Int", 0
		; 	, "Float", 1.0
		; )
		
		; Convert back to RGBA because Tesseract somehow doesn't recognize gray image
		lPix5 := DllCall("libleptonica-6.dll\pixConvertTo32", "Ptr", lPix4)
		DllCall("libleptonica-6.dll\pixDestroy", "Ptr*", &lPix4)
		
		; DllCall("libleptonica-6.dll\pixWrite", "AStr", Format("DEBUG_{}_5.jpg", A_TickCount), "Ptr", lPix5, "Int", 2)
		
		lPix5_wpl    := NumGet(lPix5, 16, "Int")  ; DllCall("libleptonica-6.dll\pixGetWpl"   ,  "Ptr", lPix5)
		lPix5_width  := NumGet(lPix5,  0, "Int")  ; DllCall("libleptonica-6.dll\pixGetWidth" ,  "Ptr", lPix5)
		lPix5_height := NumGet(lPix5,  4, "Int")  ; DllCall("libleptonica-6.dll\pixGetHeight",  "Ptr", lPix5)
		lPix5_data   := DllCall("libleptonica-6.dll\pixGetData", "Ptr", lPix5)
		byteCount := 4 * lPix5_wpl * lPix5_height
		
		If Not lPix5_data
		|| Not byteCount
			Return bufImage
		
		bufLeptonized := Buffer(byteCount)
		DllCall("msvcrt\memcpy", "Ptr", bufLeptonized, "Ptr", lPix5_data, "Ptr", byteCount)
		DllCall("libleptonica-6.dll\pixDestroy", "Ptr*", &lPix5)
		
		bufLeptonized.frameW := lPix5_width
		bufLeptonized.frameH := lPix5_height
		bufLeptonized.bytesPerLine := 4 * lPix5_wpl
		bufLeptonized.leptonized := True
		
		Return bufLeptonized
	}
}

