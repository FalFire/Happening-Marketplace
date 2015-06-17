Dom = require 'dom'
Page = require 'page'
Photo = require 'photo'

exports.render = (opts) !->
	Dom.div !->
		bgE = Dom.get()
		pageW = Page.width()
		pageH = Page.height()
		imgE = largeImgE = imgW = imgH = imgP = showW = minW = false
		offW = offH = 0
		Dom.style
			position: 'relative'
			height: pageW + 'px'
			width: pageW + 'px'
			backgroundColor: '#333'
			overflow: 'hidden'
		Dom.img !->
			imgE = Dom.get()
			Dom.style
				visibility: 'hidden'
				position: 'absolute'
			Dom.prop
				src: Photo.url(opts.key, 200)
			Dom.on 'dragstart', (e) !-> e.kill()
			Dom.setOnLoad !->
				return if !largeImgE # somehow largeImgE loaded faster
				init()

		Dom.img !->
			largeImgE = Dom.get()
			Dom.style
				visibility: 'hidden'
				position: 'absolute'
			setTimeout !->
				# allow the UI to settle before downloading larger version
				largeImgE.prop
					src: Photo.url(opts.key, false)
			,500
			Dom.on 'dragstart', (e) !-> e.kill()
			Dom.setOnLoad !->
				imgE.style display: 'none'
				imgE = largeImgE
				init()

		round = (v) -> (0|(v*10+0.05))/10

		update = !->
			showW = Math.max(showW,minW)
			scale = showW/imgW
			showH = imgH*scale

			offW = round if (empty=pageW-showW)>=0 then empty/2 else Math.max(empty,Math.min(0,offW))
			offH = round if (empty=pageW-showH)>=0 then empty/2 else Math.max(empty,Math.min(0,offH))

			bgE.style
				height: Math.ceil(Math.max(pageW,Math.min(pageH,showH+offH)))+'px'

			imgE.style
				visibility: 'visible'
				_transformOrigin: '0 0'
				_transform: "translate3d(#{offW}px,#{offH}px,0) scale3d(#{scale},#{scale},1)"

		init = !->
			imgW = imgE.prop('width')
			imgH = imgE.prop('height')
			imgP = imgH / imgW
			nw = imgW/Math.max(imgW,imgH)*pageW
			if !showW or Math.abs(showW-nw)<5
				showW = minW = nw
			update()

		startOffset = startScale = startWidth = null
		tapTime = 0
		zoomMode = null

		Dom.trackTouch (touches...) ->
			return "bubble" unless imgW

			if touches.length==1
				now = Date.now()
				touch = touches[0]
				if touch.op&4
					if touch.start + 300 > now and Math.abs(touch.x)+Math.abs(touch.y)<10 # it's a tap
						if zoomMode?
							if showW>minW
								showW = minW
							else
								showW *= 3
								offW = touch.xc - startOffset.x + (startOffset.x/startWidth) * (startWidth-showW)
								offH = touch.yc - startOffset.y + (startOffset.y/startWidth) * (startWidth-showW)
						else
							tapTime = now
					zoomMode = null
				else if touch.op&1 and tapTime+600 > now
					zoomMode = 1
				if zoomMode?
					zoomMode = Math.pow(0.99,-touch.y)

			remaining = (touch for touch in touches when !(touch.op&4))

			center = {x:0, y:0}
			for touch in remaining
				center.x += touch.xc/remaining.length
				center.y += touch.yc/remaining.length

			if remaining.length==2
				xd = remaining[0].xc - remaining[1].xc
				yd = remaining[0].yc - remaining[1].yc
				dist = Math.sqrt(xd*xd + yd*yd)
			else
				dist = 1

			for touch in touches when touch.op&5 # any starting/ending touches?
				# store a new baseline
				startOffset = {x: center.x-offW, y: center.y-offH}
				startScale = showW / dist
				startWidth = showW
				break

			showW = startScale * (zoomMode ? dist)
			offW = center.x - startOffset.x + (startOffset.x/startWidth) * (startWidth-showW)
			offH = center.y - startOffset.y + (startOffset.y/startWidth) * (startWidth-showW)
			update()

			showW==minW && !zoomMode? # scrollable if zoomed out in touchstart
		,bgE

		opts.content?()
