#Requires AutoHotkey v2.0

Class DShow {
	
	Static GUID(strGuid) {
		gBuffer := Buffer(16, 0)
		DllCall("ole32.dll\CLSIDFromString", "Str", strGuid, "Ptr", gBuffer)
		Return gBuffer
	}
	
	; To put GUID into Buffer with offset.
	Static GUIDtoPtr(strGuid, ptr) {
		Return DllCall("ole32.dll\CLSIDFromString", "Str", strGuid, "Ptr", ptr)
	}
	
	
	; Enumerates available devices for given category.
	; If 'requested' is unset, returns array of device properties (names by default).
	;   categoryClsid  - see CLSID_*Category(ies)
	;   requested      - index of device or property value to match
	;   propertyName   - one of the following: FriendlyName, Description, CLSID, DevicePath
	Static EnumerateDevices(categoryClsid := "", requested?, propertyName := "FriendlyName") {
		; Return object
		enumeratedArray := []
		
		; new SystemDeviceEnumerator
		cDevEnum := ComObject( DShow.CLSID_SystemDeviceEnum, DShow.IID_ICreateDevEnum )
		
		; IEnumMoniker := SystemDeviceEnumerator.CreateClassEnumerator()
		hResult := ComCall(3, cDevEnum
			, "Ptr"  ,  DShow.GUID(categoryClsid)
			, "Ptr*" , &outptrIEnumMoniker := 0
			, "Short",  0
		)
		
		; S_FALSE -- category does not exist or is empty
		If (hResult == 1) {
			Return []
		}
		If (hResult != 0) {
			Throw OSError("COM Call failed: SystemDeviceEnumerator.CreateClassEnumerator", -1, hResult)
		}
		
		cEnumMoniker := ComValue(13, outptrIEnumMoniker)
		
		Loop {
			; IMoniker := IEnumMoniker.Next()
			hResult := ComCall(3, cEnumMoniker
				, "UInt",  1
				, "Ptr*", &outptrIMoniker := 0
				, "Ptr" ,  0
			)
			
			; S_FALSE - end of enumeration
			If (hResult == 1)
				Break
			
			If (hResult != 0)
				Throw OSError("COM Call failed: IEnumMoniker.Next", -1, hResult)
			
			cMoniker := ComValue(13, outptrIMoniker)
			
			; IPropertyBag := IMoniker.BindToStorage()
			hResult := ComCall(9, cMoniker
				, "Ptr" ,  0
				, "Ptr" ,  0
				, "Ptr" ,  DShow.GUID(DShow.IID_IPropertyBag)
				, "Ptr*", &outptrIPropertyBag := 0
			)
			
			If (hResult != 0)
				Throw OSError("COM Call failed: IMoniker.BindToStorage", -1, hResult)
			
			cPropertyBag := ComValue(13, outptrIPropertyBag)
			
			; Helper function to get Moniker's properties
			GetPropertyFromBag(cBag, strProperty) {
				variantBuffer := Buffer(24, 0)
				
				hResult := ComCall(3, cPropertyBag
					, "Str" , strProperty
					, "Ptr" , variantBuffer
					, "Ptr" , 0
				)
				; TODO: Support for WaveInID
				; Retrieve property value from BSTR
				propertyValue := (hResult == 0) ? StrGet(NumGet(variantBuffer, 0+8, "Ptr")) : ""
				DllCall("oleaut32.dll\VariantClear", "Ptr", variantBuffer)
				
				Return propertyValue
			}
			
			monikerProp := GetPropertyFromBag(cPropertyBag, propertyName)
			
			If Not IsSet(requested) {
				enumeratedArray.Push(monikerProp)
				Continue
			}
			
			If ((requested Is String)  && (requested == monikerProp))
			|| ((requested Is Integer) && (requested == A_Index))
			{
				; IBaseFilter := IMoniker.BindToObject
				hResult := ComCall(8, cMoniker
					, "Ptr" ,  0
					, "Ptr" ,  0
					, "Ptr" ,  DShow.GUID(DShow.IID_IBaseFilter)
					, "Ptr*", &outptrIBaseFilter := 0
				)
				
				If (hResult != 0)
					Throw OSError("COM Call failed: IMoniker.BindToObject", -1, hResult)
				
				Return ComValue(13, outptrIBaseFilter)
			}
		}
		
		If Not IsSet(requested)
			Return enumeratedArray
		
		Return
	}
	
	
	Class Capture {
		
		__New() {
			this.cFilterGraph  := ComObject( DShow.CLSID_FilterGraph, DShow.IID_IGraphBuilder )
			this.cCaptureGraph := ComObject( DShow.CLSID_CaptureGraphBuilder2, DShow.IID_ICaptureGraphBuilder2 )
			
			hResult := ComCall(3, this.cCaptureGraph, "Ptr", this.cFilterGraph)
			If (hResult != 0) {  ; S_OK
				Throw OSError("COM Call failed: CaptureGraphBuilder2.SetFiltergraph", -1, hResult)
			}
			
			this.cCaptureFilter := 0
			this.cGrabberFilter := 0
			this.cNullRenderFilter := 0
		}
		
		__Delete() {
			this.cMediaControl     := 0
			this.cNullRenderFilter := 0
			this.cSampleGrabber    := 0
			this.cGrabberFilter    := 0
			this.cCaptureFilter    := 0
			this.cCaptureGraph     := 0
			this.cFilterGraph      := 0
		}
		
		
		GetVideoInputDeviceList() {
			Return DShow.EnumerateDevices(DShow.CLSID_VideoInputDeviceCategory)
		}
		
		
		SetCaptureDevice(requestedDevice) {
			this.cCaptureFilter := 0
			cCaptureFilter := DShow.EnumerateDevices(DShow.CLSID_VideoInputDeviceCategory, requestedDevice)
			
			If Not IsObject(cCaptureFilter) {
				Throw Error("Unable to create capture device filter", -1)
			}
			
			this.cCaptureFilter := cCaptureFilter
		}
		
		
		StartCapture( showPreview := False ) {
			If Not IsObject(this.cCaptureFilter)
				Return False
			
			this.cGrabberFilter    := ComObject( DShow.CLSID_SampleGrabber, DShow.IID_IBaseFilter )
			this.cNullRenderFilter := ComObject( DShow.CLSID_NullRenderer , DShow.IID_IBaseFilter )
			
			; SampleGrabber's own interface to be set up
			this.cSampleGrabber := ComObjQuery( this.cGrabberFilter, DShow.IID_ISampleGrabber )
			
			; ISampleGrabber.SetBufferSamples(True)
			hResult := ComCall(6, this.cSampleGrabber,  "Int", True)
			If (hResult != 0)
				Throw OSError("COM Call failed: ISampleGrabber.SetOneShot", -1, hResult)
			
			bMediaType := Buffer(16+16+16+8+4*A_PtrSize, 0)  ; AM_MEDIA_TYPE
			DShow.GUIDtoPtr( DShow.MEDIATYPE_Video   , bMediaType.Ptr +  0 )
			DShow.GUIDtoPtr( DShow.MEDIASUBTYPE_RGB32, bMediaType.Ptr + 16 )
			
			hResult := ComCall(4, this.cSampleGrabber, "Ptr", bMediaType)
			If (hResult != 0)
				Throw OSError("COM Call failed: ISampleGrabber.SetMediaType", -1, hResult)
			
			; Add filters to FilterGraph
			For cFilter, filterName In Map(
				this.cCaptureFilter, "Capture Filter",
				this.cGrabberFilter, "Sample Grabber",
				this.cNullRenderFilter, "Null Renderer"
			) {
				; IFilterGraph.AddFilter()
				hResult := ComCall(3, this.cFilterGraph
					, "Ptr", cFilter
					, "Str", filterName
				)
				If (hResult != 0)
					Throw OSError("COM Call failed: IFilterGraph.AddFilter", -1, hResult)
			}
			
			; ICaptureGraphBuilder2.RenderStream
			hResult := ComCall(7, this.cCaptureGraph
				, "Ptr", DShow.GUID(DShow.PIN_CATEGORY_CAPTURE)
				, "Ptr", DShow.GUID(DShow.MEDIATYPE_Video)
				, "Ptr", this.cCaptureFilter
				, "Ptr", this.cGrabberFilter
				, "Ptr", this.cNullRenderFilter
			)
			If (hResult != 0)
				Throw OSError("COM Call failed: ICaptureGraphBuilder2.RenderStream", -1, hResult)
			
			; Preview Window
			If (showPreview) {
				hResult := ComCall(7, this.cCaptureGraph
					, "Ptr", DShow.GUID(DShow.PIN_CATEGORY_PREVIEW)
					, "Ptr", DShow.GUID(DShow.MEDIATYPE_Video)
					, "Ptr", this.cCaptureFilter
					, "Ptr", 0
					, "Ptr", 0
					, "Int"
				)
				If (hResult != 0)
				&& (hResult != 0x0004027E)  ; VWF_S_NOPREVIEWPIN
					Throw OSError("COM Call failed: ICaptureGraphBuilder2.RenderStream", -1, hResult)
			}
			
			; Get MediaControl interface of the FilterGraph.
			; IMediaControl implements IDispatch interface,
			; so it should be usable in the script with regular object syntax.
			cIMediaControl := ComObjQuery(this.cFilterGraph, DShow.IID_IMediaControl)
			ObjAddRef(cIMediaControl.Ptr)
			this.cMediaControl := ComObjFromPtr(cIMediaControl.Ptr)
			
			this.ResumeCapture()
		}
		
		ResumeCapture() {
			this.cMediaControl.Run()
		}
		
		StopCapture() {
			this.cMediaControl.Stop()
		}
		
		GrabFrame() {
			; Get required buffer size
			; ISampleGrabber.GetCurrentBuffer()
			hResult := ComCall(7, this.cSampleGrabber
				, "Int*", &outBufferSize := 0
				, "Ptr" ,  0
				, "Int"       ; Using Int prevents error on VFW_E_WRONG_STATE
			)
			
			; VFW_E_WRONG_STATE - FilterGraph still starting up.
			If (hResult & 0xFFFFFFFF == 0x80040227)
				Return 0
			
			If (hResult != 0)
				Throw OSError("COM Call failed: ISampleGrabber.GetCurrentBuffer", -1, hResult)
			
			If (outBufferSize == 0)
				Return 0
			
			; Get buffer data
			bFrameData := Buffer(outBufferSize, 0)
			; ISampleGrabber.GetCurrentBuffer()
			hResult := ComCall(7, this.cSampleGrabber
				, "Int*", &outBufferSize
				, "Ptr" ,  bFrameData
			)
			
			If (hResult != 0)
				Throw OSError("COM Call failed: ISampleGrabber.GetCurrentBuffer", -1, hResult)
			
			; Validate sample media type
			bMediaType := Buffer(16+16+16+8+4*A_PtrSize)
			; ISampleGrabber.GetConnectedMediaType
			hResult := ComCall(5, this.cSampleGrabber, "Ptr", bMediaType)
			If (hResult != 0)
				Throw OSError("COM Call failed: ISampleGrabber.GetConnectedMediaType", -1, hResult)
			
			VarSetStrCapacity(&mtFormatType, 39)
			DllCall("ole32.dll\StringFromGUID2"
				, "Ptr", bMediaType.Ptr + 16+16+4+4+4  ; AMMediaType.formattype
				, "Str", mtFormatType
				, "Int", 39
			)
			
			If (StrCompare(mtFormatType, DShow.FORMAT_VideoInfo) != 0)
				Throw Error("Wrong sample media type", -1, mtFormatType)
			
			mtCbFormat := NumGet(bMediaType, 16+16+16+8+A_PtrSize+A_PtrSize, "UInt")
			If (mtCbFormat != 88)
				Throw Error("Wrong VIDEOINFOHEADER struct size", -1, mtCbFormat)
			
			; Read frame properties from BITMAPINFOHEADER
			ptrVIHeader := NumGet(bMediaType, 16+16+16+8+3*A_PtrSize, "Ptr")  ; AMMediaType.pbFormat
			bmiHeaderOffset := 16+16+4+4+8
			bFrameData.frameW := NumGet(ptrVIHeader, bmiHeaderOffset+4, "Int")
			bFrameData.frameH := NumGet(ptrVIHeader, bmiHeaderOffset+8, "Int")
			
			Return bFrameData
		}
	}
	
	
	Static CLSID_VideoInputDeviceCategory := "{860BB310-5D01-11D0-BD3B-00A0C911CE86}"
	Static CLSID_AudioInputDeviceCategory := "{33D9A762-90C8-11D0-BD43-00A0C911CE86}"
	Static CLSID_ActiveMovieCategories    := "{DA4E3DA0-D07D-11D0-BD50-00A0C911CE86}"
	Static CLSID_LegacyAmFilterCategory   := "{083863F1-70DE-11D0-BD40-00A0C911CE86}"
	Static CLSID_VideoCompressorCategory  := "{33D9A760-90C8-11D0-BD43-00A0C911CE86}"
	Static CLSID_AudioCompressorCategory  := "{33D9A761-90C8-11D0-BD43-00A0C911CE86}"
	Static CLSID_AudioRendererCategory    := "{E0F158E1-CB04-11D0-BD4E-00A0C911CE86}"  ; Audio renderer category
	Static CLSID_MidiRendererCategory     := "{4EFE2452-168A-11D1-BC76-00C04FB9453B}"  ; Midi renderer category
	Static CLSID_TransmitCategory         := "{CC7BFB41-F175-11D1-A392-00E0291F3959}"  ; External Renderers Category
	Static CLSID_DeviceControlCategory    := "{CC7BFB46-F175-11D1-A392-00E0291F3959}"  ; Device Control Filters
	
	Static CLSID_SystemDeviceEnum := "{62BE5D10-60EB-11D0-BD3B-00A0C911CE86}"
	Static   IID_ICreateDevEnum   := "{29840822-5B84-11D0-BD3B-00A0C911CE86}"
	;	== ICreateDevEnum ==
	;	.. IUnknown ..
	;	3	CreateClassEnumerator(This,clsidDeviceClass,ppEnumMoniker,dwFlags)
	
	Static IID_IEnumMoniker := "{00000102-0000-0000-C000-000000000046}"
	;	== IEnumMoniker ==
	;	.. IUnknown ..
	;	3	Next(This,celt,rgelt,pceltFetched)
	;	4	Skip(This,celt)
	;	5	Reset(This)
	;	6	Clone(This,ppenum)
	
	Static IID_IMoniker := "{0000000F-0000-0000-C000-000000000046}"
	;	== IMoniker ==
	;	.. IUnknown ..
	;	.. IPersist ..
	;	.. IPersistStream ..
	;	8	BindToObject(This,pbc,pmkToLeft,riidResult,ppvResult)
	;	9	BindToStorage(This,pbc,pmkToLeft,riid,ppvObj)
	;	...
	
	Static IID_IPropertyBag := "{55272A00-42CB-11CE-8135-00AA004BB851}"
	;	== IPropertyBag ==
	;	.. IUnknown ..
	;	3	Read(This,pszPropName,pVar,pErrorLog)
	;	4	Write(This,pszPropName,pVar)
	
	Static CLSID_FilterGraph  := "{E436EBB3-524F-11CE-9F53-0020AF0BA770}"  ; Filter Graph
	Static   IID_IFilterGraph := "{56A8689F-0AD4-11CE-B03A-0020AF0BA770}"
	;	== IFilterGraph ==
	;	.. IUnknown ..
	;	3	AddFilter(This,pFilter,pName)
	;	4	RemoveFilter(This,pFilter)
	;	5	EnumFilters(This,ppEnum)
	;	6	FindFilterByName(This,pName,ppFilter)
	;	7	ConnectDirect(This,ppinOut,ppinIn,pmt)
	;	8	Reconnect(This,ppin)
	;	9	Disconnect(This,ppin)
	;	10	SetDefaultSyncSource(This)
	
	Static IID_IGraphBuilder := "{56A868A9-0AD4-11CE-B03A-0020AF0BA770}"
	;	== IGraphBuilder ==
	;	.. IFilterGraph ..
	;	11	Connect(This,ppinOut,ppinIn)
	;	12	Render(This,ppinOut)
	;	13	RenderFile(This,lpcwstrFile,lpcwstrPlayList)
	;	14	AddSourceFilter(This,lpcwstrFileName,lpcwstrFilterName,ppFilter)
	;	15	SetLogFile(This,hFile)
	;	16	Abort(This)
	;	17	ShouldOperationContinue(This)
	
	
;	Static CLSID_CaptureGraphBuilder   := "{BF87B6E0-8C27-11D0-B3F0-00AA003761C5}"  ; Capture graph building (deprecated)
	Static CLSID_CaptureGraphBuilder2  := "{BF87B6E1-8C27-11D0-B3F0-00AA003761C5}"  ; New Capture graph building
	Static   IID_ICaptureGraphBuilder2 := "{93E5A4E0-2D50-11D2-ABFA-00A0C9C6E38D}"
	;	== ICaptureGraphBuilder2 ==
	;	.. IUnknown ..
	;	3	SetFiltergraph(This,pfg)
	;	4	GetFiltergraph(This,ppfg)
	;	5	SetOutputFileName(This,pType,lpstrFile,ppf,ppSink)
	;	6	FindInterface(This,pCategory,pType,pf,riid,ppint)
	;	7	RenderStream(This,pCategory,pType,pSource,pfCompressor,pfRenderer)
	;	8	ControlStream(This,pCategory,pType,pFilter,pstart,pstop,wStartCookie,wStopCookie)
	;	9	AllocCapFile(This,lpstr,dwlSize)
	;	10	CopyCaptureFile(This,lpwstrOld,lpwstrNew,fAllowEscAbort,pCallback)
	;	11	FindPin(This,pSource,pindir,pCategory,pType,fUnconnected,num,ppPin)
	
	Static IID_IBaseFilter := "{56A86895-0AD4-11CE-B03A-0020AF0BA770}"
	;	.. IUnknown ..
	;	-- IPersist --
	;	3	GetClassID(This,pClassID)
	;	-- IMediaFilter --
	;	4	Stop(This)
	;	5	Pause(This)
	;	6	Run(This,tStart)
	;	7	GetState(This,dwMilliSecsTimeout,State)
	;	8	SetSyncSource(This,pClock)
	;	9	GetSyncSource(This,pClock)
	;	-- IBaseFilter --
	;	10	EnumPins(This,ppEnum)
	;	11	FindPin(This,Id,ppPin)
	;	12	QueryFilterInfo(This,pInfo)
	;	13	JoinFilterGraph(This,pGraph,pName)
	;	14	QueryVendorInfo(This,pVendorInfo)
	
	Static CLSID_NullRenderer   := "{C1F400A4-3F08-11D3-9F0B-006008039E37}"
	
	Static CLSID_SampleGrabber  := "{C1F400A0-3F08-11d3-9F0B-006008039E37}"
	Static   IID_ISampleGrabber := "{6B652FFF-11FE-4FCE-92AD-0266B5D7C78F}"
	;	== ISampleGrabber ==
	;	.. IUnknown ..
	;	3	SetOneShot(This,OneShot)
	;	4	SetMediaType(This,pType)
	;	5	GetConnectedMediaType(This,pType)
	;	6	SetBufferSamples(This,BufferThem)
	;	7	GetCurrentBuffer(This,pBufferSize,pBuffer)
	;	8	GetCurrentSample(This,ppSample)
	;	9	SetCallback(This,pCallback,WhichMethodToCallback)
	
	; Note: IMediaControl implements IDispatch interface,
	; so it should be possible to use it in AHK directly.
	Static IID_IMediaControl := "{56A868B1-0AD4-11CE-B03A-0020AF0BA770}"
	;	== IMediaControl ==
	;	.. IUnknown methods ..
	;	.. IDispatch methods ..
	;	7	Run(This)
	;	8	Pause(This)
	;	9	Stop(This)
	;	10	GetState(This,msTimeout,pfs)
	;	11	RenderFile(This,strFilename)
	;	12	AddSourceFilter(This,strFilename,ppUnk)
	;	13	get_FilterCollection(This,ppUnk)
	;	14	get_RegFilterCollection(This,ppUnk)
	;	15	StopWhenReady(This)
	
	Static PIN_CATEGORY_CAPTURE := "{FB6C4281-0353-11D1-905F-0000C0CC16BA}"
	Static PIN_CATEGORY_PREVIEW := "{FB6C4282-0353-11D1-905F-0000C0CC16BA}"
	Static MEDIATYPE_Stream     := "{E436EB83-524F-11CE-9F53-0020AF0BA770}"
	Static MEDIATYPE_Video      := "{73646976-0000-0010-8000-00AA00389B71}"  ; 'vids'
	Static MEDIATYPE_Audio      := "{73647561-0000-0010-8000-00AA00389B71}"  ; 'auds'
	Static MEDIASUBTYPE_RGB24   := "{E436EB7D-524F-11CE-9F53-0020AF0BA770}"
	Static MEDIASUBTYPE_RGB32   := "{E436EB7E-524F-11CE-9F53-0020AF0BA770}"
	
	Static FORMAT_None          := "{0F6417D6-C318-11D0-A43F-00A0C9223196}"
	Static FORMAT_VideoInfo     := "{05589F80-C356-11CE-BF01-00AA0055595A}"
	Static FORMAT_WaveFormatEx  := "{05589F81-C356-11CE-BF01-00AA0055595A}"
	Static FORMAT_MPEGVideo     := "{05589F82-C356-11CE-BF01-00AA0055595A}"
}