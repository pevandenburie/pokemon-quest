-- title:  POKEMON QUEST
-- author: Deck http://deck.itch.io
-- desc:   roguelike game
-- script: lua
-- input:  gamepad

-- constants
local CAM_W=240
local CAM_H=136
local MAP_W=1920
local MAP_H=1088
local CELL=8
local DCELL=16	-- Double cell


local tiles={
	ROCK=4,
	TREE=2,
}

local animated_tiles={
	WATER
}

local SOLID_TILES_FROM=2
local SOLID_TILES_TO=87

--controls
c={
	UP=0,
	DOWN=1,
	LEFT=2,
	RIGHT=3,
	z=4, --A
	x=5, --B
	a=6,
	s=7
}

-- global variables
local t=0	-- global time, used in TIC() method
local cam={x=0,y=0}
local mobs={}
local firstRun=true
local figthPk=nil

-- init
local p1

-- debug utilities
local function PrintDebug(object)
	for i,v in pairs(object) do
		-- printable elements
		if type(v)~="table" and type(v)~="boolean" and type(v)~="function" and v~=nil then
			trace("["..i.."] "..v)
		-- boolean
		elseif type(v)=="boolean" then
			trace("["..i.."] "..(v and "true" or "false"))
		-- table, only ids
		elseif type(v)=="table" then
			local txt="["
			for y,k in pairs(v) do
				txt=txt..(y..",")
			end
			txt=txt.."]"
			trace("["..i.."] "..txt)
		-- function
		elseif type(v)=="function" then
			trace("["..i.."] ".."function")
		end
	end		
	trace("------------------")
end


------------------------------------------
-- Message Box class
local function MessageBox()
	local MSG_TIMEOUT=60*3
	local box={
		msg=nil,
		timeout=MSG_TIMEOUT
	}

	function box.Push(msg, timeout)
		if msg~=nil then
			box.msg=msg
			box.timeout=timeout or MSG_TIMEOUT
		end
	end

	function box.Display()
		if box.msg then
			box.timeout=box.timeout-1
			if box.timeout<=0 then
				box.Clear()
			else
				local BOX_X=0
				local BOX_Y=12*CELL
				local BOX_W=CAM_W-2*BOX_X
				local BOX_H=CAM_H-BOX_Y
				rect(BOX_X,BOX_Y,BOX_W,BOX_H,15)
				rectb(BOX_X+2,BOX_Y+2,BOX_W-4,BOX_H-4,0)
				local width=print(box.msg,0,-6)
				print(box.msg,(BOX_W-width)//2,(BOX_Y+(BOX_H-6)//2),0)
			end
		end
	end

	function box.Clear()
		box.msg=nil
		timeout=MSG_TIMEOUT
	end

	return box
end

-- GLobal message box
local msgBox = MessageBox()

------------------------------------------
-- collision class
local Collision={}

function Collision:GetEdges(x,y,w,h)
	local w=w or CELL-1
	local h=h or CELL-1
	local x=x+(CELL-w)/2
	local y=y+(CELL-h)/2
	
	-- get the map ids in the edges	
	local topLeft=mget(x/CELL,y/CELL)
	local topRight=mget((x+w)/CELL,y/CELL)
	local bottomLeft=mget(x/CELL,(y+h)/CELL)
	local bottomRight=mget((x+w)/CELL,(y+h)/CELL)
	
	return topLeft,topRight,bottomLeft,bottomRight
end

function Collision:CheckSolid(indx)
	-- trace(indx)
	if (indx>=SOLID_TILES_FROM) and (indx<=SOLID_TILES_TO) then
		return true
	end
	return false
	-- return indx==tiles.ROCK or					
	-- 	indx==tiles.TREE
end


------------------------------------------
-- animation class
local function Anim(span,frames,loop)
	local s={
		span=span or 60,
		frame=0,
		loop=loop==nil and true or false, -- this code sucks!
		tick=0,
		indx=0,
		frames=frames or {},
		ended=false
	}
	
	function s.Update(time)
		if time>=s.tick and #s.frames>0 then
			if s.loop then
				s.indx=(s.indx+1)%#s.frames
				s.frame=s.frames[s.indx+1]
				s.ended=false
			else
				s.indx=s.indx<#s.frames and s.indx+1 or #s.frames
				s.frame=s.frames[s.indx]
				if s.indx==#s.frames then s.ended=true end
			end
			s.tick=time+s.span
		end 
	end
	
	function s.RandomIndx()
		s.indx=math.random(#s.frames)
	end
	
	function s.Reset()
			s.indx=0
			s.ended=false
	end
	
	return s
end


------------------------------------------
-- mob class
local function Mob(x,y,player)
	local s={
		tag="mob",
		x=x or 0,
		y=y or 0,
		alpha=8,
		anims={},	-- idle, walk, attack, die, damaged
		fov=6*CELL,
		proximity=CELL-2,		
		dx=0,
		dy=0,
		flip=false,
		visible=true,
		curAnim=nil,
		tick=0,
		player=player,
		speed=0.3+math.random()*0.1
	}
	
	function s.Move(dx,dy,walkAnim)
		-- store deltas, they could be useful
		s.dx=dx
		s.dy=dy
		
		-- detect flip
		if dx~=0 then s.flip=dx<0 and 1 or 0 end
		
		-- next position
		local nx=s.x+dx
		local ny=s.y+dy
	
		-- check the collision on the edges
		local tl,tr,bl,br=Collision:GetEdges(nx,ny,CELL-2,CELL-2)
		
		if not Collision:CheckSolid(tl) and not
				 Collision:CheckSolid(tr) and not
				 Collision:CheckSolid(bl) and not
				 Collision:CheckSolid(br) then
			s.x=nx
			s.y=ny
			-- if not s.damaged then s.curAnim=s.anims.walk end
			s.curAnim=walkAnim
		else
			s.curAnim=s.anims.idle
		end
	
    	-- bounds
		if s.x<0 then s.x=0 end
		if s.x>MAP_W-CELL then s.x=MAP_W-CELL end
		if s.y<0 then s.y=0 end
		if s.y>MAP_H-CELL then s.y=MAP_H-CELL end
	end
	
	function s.Update(time)
		-- detect if we are in the camera bounds
		s.visible=s.x>=cam.x and s.x<=cam.x+CAM_W-CELL and s.y>=cam.y and s.y<=cam.y+CAM_H-CELL
	
		-- default: idle
		s.curAnim=s.anims.idle
	end
	
	function s.Display(time)
		if s.curAnim==nil then return end
		s.curAnim.Update(time)
		-- arrangement to correctly display it in the map
		local x=(s.x-cam.x)%CAM_W
		local y=(s.y-cam.y)%CAM_H
		if s.visible then
			spr(s.curAnim.frame,x,y,s.alpha,1,s.flip)
			-- rectb(x,y,CELL,CELL,14)
		end		
	end

	return s
end



------------------------------------------
-- player:mob class
local function Player(x,y)
	local s=Mob(x,y)
	s.tag="player"
	s.facing=c.DOWN
	
	s.anims={
		idle=Anim(60,{258}),
		walkLeft=Anim(10,{262,264,266,264}),
		walkRight=Anim(10,{262,264,266,264}),
		walkUp=Anim(10,{288,290,292,290}),
		walkDown=Anim(10,{256,258,260,258}),
	}
	
	-- store the super method
	local supMove=s.Move
	
	function s.Move(dx,dy,walkAnim)
		-- call super.move
		supMove(dx,dy,walkAnim)
		
		-- flip
		if dx~=0 then s.flip=dx<0 and 1 or 0 end
	end
	
	function s.Update(time)		
		s.dx=0
		s.dy=0
		
		-- default: idle
		s.curAnim=s.anims.idle

		s.Controls()

		-- check environment messages
		for i,static in pairs(statics) do
			-- collision detected
			if math.abs(s.x-static.x)<CELL and math.abs(s.y-static.y)<CELL then
				-- get message
				msgBox.Push(static.GetMsg(), 60)
				-- call attached callback
				static.cb(static.param)
			end
		end
	end
	
	function s.Controls()
		-- manage the user input
		-- arrows [0,1,2,3].......movement
		-- z [4].........................attack
		-- x [5].........................healing
		if btn(c.UP) then 
			s.facing=c.UP
			s.Move(0,-1,s.anims.walkUp)
		end
		if btn(c.DOWN) then 
			s.facing=c.DOWN
			s.Move(0,1,s.anims.walkDown)
		end
		if btn(c.LEFT) then 
			s.facing=c.LEFT
			s.Move(-1,0,s.anims.walkLeft)
		end
		if btn(c.RIGHT) then
			s.facing=c.RIGHT
			s.Move(1,0,s.anims.walkRight)
		end
		if btn(c.z) then
			-- clear message if any
			msgBox.Clear()
		end
	end
	
	function s.Display(time)
		if s.curAnim==nil then return end
		s.curAnim.Update(time)
		-- assure that the player is always in the camera bounds
		spr(s.curAnim.frame,s.x%(CAM_W-CELL),s.y%(CAM_H-CELL),s.alpha,1,s.flip,0,2,2)
		-- rectb(s.x+s.dx*3+(CELL-2)/2,s.y+s.dy*3+(CELL-2)/2,2,2,14)
	end
	
	return s
end


------------------------------------------
-- Static Item class
local function StaticItem(x,y,anim,tag,cb,param)
	local s={
		tag=tag or "staticItem",
		x=x or 0,
		y=y or 0,
		alpha=8,
		curAnim=anim,  -- [] only one anim
		visible=true,
		flip=false,
		msg="Hi!",
		cb=cb or function(p) trace("hello") end, -- default callback
		param=param or "NA"
	}

	function s.Update(time)
		-- detect if we are in the camera bounds
		s.visible=s.x>=cam.x and s.x<=cam.x+CAM_W-CELL and s.y>=cam.y and s.y<=cam.y+CAM_H-CELL
		
		-- do something at the end of the animation
		-- int the case of the mob stop to stay in particular states
		-- if s.curAnim~=nil and s.curAnim.ended then
		-- 	-- s.died=false
		-- 	s.attack=false
		-- 	s.damaged=false
		-- end
	end

	function s.Display(time)
		if s.curAnim==nil then return end
		s.curAnim.Update(time)
		local x=(s.x-cam.x)%CAM_W
		local y=(s.y-cam.y)%CAM_H
		if s.visible then
			-- trace("Show "..s.tag.." anim "..s.curAnim.frame)
			spr(s.curAnim.frame,x,y,s.alpha,1,s.flip,0,2,2)
			-- rectb(x,y,CELL,CELL,14)
		end
	end

	function s.GetMsg()
		return s.msg
	end

	return s
end

local function SpawnStaticItem(cellX,cellY,anim,tag,msg,cb,param)
	local s=StaticItem(cellX*CELL,cellY*CELL,anim,tag,cb,param)
	s.msg=msg
	table.insert(statics, s)
end

local function Pokemon(name,spr,pv)
	local pk={
		name=name or "unkown",
		spr=spr,
		pv=pv or 0
	}
	return pk
end

local POKEMONS={
	PIKACHU=Pokemon("Pikachu",268,40),
	SALAMECHE=Pokemon("Salameche",270,30),
	BULBIZARRE=Pokemon("Bulbizarre",300,30)
}

local function StartFight(pk1,pk2)
	trace("StartFight")
	PrintDebug(pk1)
	trace(pk1)
	PrintDebug(pk2)
	-- draw scene
	local BOX_X=4*CELL
	local BOX_Y=4*CELL
	local BOX_W=CAM_W-2*BOX_X
	local BOX_H=10*CELL
	rect(BOX_X,BOX_Y,BOX_W,BOX_H,15)
	rectb(BOX_X+2,BOX_Y+2,BOX_W-4,BOX_H-4,0)

	-- draw pokemons
	x=BOX_X+4*CELL
	y=BOX_Y+4*CELL
	alpha=8
	flip=false
	spr(pk1.spr,x,y,alpha,1,flip,0,2,2)
	
	x=BOX_X+BOX_W-6*CELL
	y=BOX_Y+4*CELL
	alpha=8
	flip=false
	spr(pk2.spr,x,y,alpha,1,flip,0,2,2)
	-- show PV
	-- show available attacks
	trace("OK!")
end

local function StartFightCb(pk)
	figthPk=pk
end

local function SpawnPokemon(cellX,cellY,pk)
	SpawnStaticItem(cellX,cellY,Anim(20,{pk.spr}),pk.name,"Vous avez trouvé un Pokemon!",StartFightCb,pk)
end

local function SpawnPikachu(statics,cellX,cellY)
	local pk=POKEMONS.PIKACHU -- Pokemon("Pikachu",268,30)
	SpawnStaticItem(cellX,cellY,Anim(20,{268}),pk.name,"Vous avez trouvé Pikachu!",StartFightCb,pk)
end

local function SpawnSalameche(statics,cellX,cellY)
	local pk=POKEMONS.SALAMECHE -- Pokemon("Salameche",268,30)
	SpawnStaticItem(cellX,cellY,Anim(20,{270}),pk.name,"Vous avez trouvé Salameche!",StartFightCb,pk)
end

local function SpawnSign(statics,cellX,cellY)
	SpawnStaticItem(cellX,cellY,null,"Sign","M. Choo")
end


local function Init()
	-- detect if run for the fisrt time
	if not firstRun then return end
	firstRun=false
	
	-- clear tables
	statics={}
	mobs={}
	-- animTiles={}
	
	-- create player
	p1=Player(8*CELL,6*CELL)
	p1.pk=POKEMONS.PIKACHU

	-- Add statics items
	SpawnSign(statics,15,6)

	-- Add Pokemons
	SpawnPokemon(17,14,POKEMONS.PIKACHU)
	SpawnPokemon(20,2,POKEMONS.BULBIZARRE)
	SpawnPokemon(2,14,POKEMONS.SALAMECHE)

	-- cycle the map and manage the special elements
	for y=0,MAP_W/CELL do
		for x=0,MAP_H/CELL do	
			-- animated tiles
			if mget(x,y)==tiles.LAVA_1 or mget(x,y)==tiles.LAVA_2 or mget(x,y)==tiles.LAVA_3 then
				local tile=AnimTile(x,y,Anim(30,{tiles.LAVA_1,tiles.LAVA_2,tiles.LAVA_3}))
				tile.anim.RandomIndx()
				table.insert(animTiles,tile)
			end
		end
	end

	msgBox.Push("Bienvenue dans cette quete Pokemon!")
end

------------------------------------------				
-- main
function TIC()
	-- runs only the first time or to reset the game
	Init()
	-- reset the game if the player is died and is pressed x
	-- if btn(5) and p1.died then firstRun=true end
	-- if btn(5) and boss.died then firstRun=true end
	
	-- set the camera and draw the background
	cam.x=p1.x-p1.x%(CAM_W-CELL)
	cam.y=p1.y-p1.y%(CAM_H-CELL)
	-- cls(3)
	map(cam.x/CELL,cam.y/CELL,CAM_W/CELL,CAM_H/CELL)
	-- map(cam.x/CELL,cam.y/CELL,CAM_W/CELL,CAM_H/CELL,0,0,-1,2)
	
	if figthPk then
		StartFight(p1.pk,figthPk)
	else

	------------- UPDATE -------------
	-- statics
	for i,statics in pairs(statics) do statics.Update(t) end
	-- mobs
	for i,mob in pairs(mobs) do mob.Update(t) end
	
	-- player
	p1.Update(t)
	
	------------- DISPLAY -------------
	-- statics
	for i,statics in pairs(statics) do statics.Display(t) end
	-- mobs
	for i,mob in pairs(mobs) do mob.Display(t) end
	-- player
	p1.Display(t)

	-- Show message if needed
	msgBox.Display()

	-- increment global time
	t=t+1

	end
end
-- <TILES>
-- 000:4444444444444444444444444445444444444444444445444444444444444444
-- 001:4444444412441244122212221111111112441244124412441244124444444444
-- 002:4444444445444044444005044405555040550055050055550040550044055002
-- 003:4444444444004444405504440555500455555504000555500440055004544000
-- 004:4444444445444444444400004400777744077a77440777a740a7777740a77777
-- 005:444444444445444400044445770004447f7700447ff7704477ff770477777704
-- 016:4400004440000004401002044012220440122204401222044012220444000044
-- 018:4405040245004402444444004444444044455444444444444544444544444445
-- 019:0444444420444444220444542204444402204444022045440525444455555444
-- 020:40a7a77740a7aa77400a7777440055a74445555a445455554444444444444444
-- 021:7777770477aa770477777004757700445aa50444555454444444444444444454
-- 032:2222222266666666666666660666066606660666600060006666666606660666
-- 033:0000000066666666600060000666066606660666666666666000600006660666
-- 048:0666066660006000666666660666066606660666600060006666666600000000
-- 049:0666066666666666600060000666066606660666666666666666666622222222
-- 064:077eeeee077aeeee0aaeeeee0eeeeeee0eeeeeee0eeee77e0eeeeeee0eeeeeee
-- 065:eeeeeeeee000000e0fff8f900ff8f9800f8f989008f989900f989990e000000e
-- 066:a7777777aaaaaaaa00000000a7012212a7012212a7012212a7012212a7012212
-- 067:77777777aaaaaaa700000000212220a7212220a7212220a7212220a7212220a7
-- 068:eeeeeeeee000000e0fff8f900ff8f9800f8f989008f989900f989990e000000e
-- 069:eeeee770eeeea770eeeeeaa0eeeeeee0eeeeeee0e77eeee0eeeeeee0eeeeeee0
-- 080:0eeeeeee0eeeeeee0eeeeeee0ea777ee0eaaaeee0eeeeeee0000000044444444
-- 081:eeeeeeeeeeeeeeeeeea77eeeeea777eeeeeaaeeeeeeeeeee0000000044444444
-- 082:a7012212a7012212a7012212a7012212a7012212a7012212a701221200000000
-- 083:212a20a721a2a0a7212a20a7212220a7212220a7212220a7212220a700000000
-- 084:eeeeeeeeeeeeeeeeeea77eeeeea777eeeeeaaeeeeeeeeeee0000000044444444
-- 085:eeeeeee0eeeeeee0eeeeeee0ee777ae0eeeaaae0eeeeeee00000000044444444
-- 096:4444444444446664446646664464666446446111444416114444161144416111
-- 097:4444444466444444464444444464444464644444644644446444444461444444
-- 112:4441161644111616444116164441161644411616444166164411611641111616
-- 113:1114444411014444111444441144444411144444111144441111144411111144
-- 128:4444444444004000401202224012000040120444401204004012040e4012040e
-- 129:444444440000000422222220000000040444044400000004eeeeee0400e0ee04
-- 144:4012040e4012040e4012040e4012044040120444401204444012045444004444
-- 145:eeeeee040e000e04eeeeee040000004444444444455444444444445444444544
-- 208:4444444444488f84448ff888488888ff4f88ff8844ff88ff4488f8884f888f88
-- 209:4444444484f844888f8ff888f88888ff8f88ff8888ff88ff8f88f8888f888f88
-- 210:4444444484f844448f8ff844f88888f48f88ff8488ff88448f88f8448f888f84
-- 224:48f888f848f88f88448ff888448888ff4f88ff8848ff88ff4f88f8884f888f88
-- 225:88f888f888f88f888f8ff888f88888ff8f88ff8888ff88ff8f88f8888f888f88
-- 226:88f888f488f88f848f8ff844f88888f48f88ff8488ff88448f88f8848f888f84
-- 240:48f888f848f88f884f8ff888448888ff4488ff8844ff88ff4448f44844444444
-- 241:88f888f888f88f888f8ff888f88888ff8f88ff8888ff88ff8f84444844444444
-- 242:88f888f488f88f848f8ff884f88888f48f88ff4488ff88448f48f44444444444
-- 243:eeeeeeeeeeeeeeeeedeeeedeeeeeeeeeeeeeeeeeeeeeedeeeeedeeeeeeeeeeee
-- 245:888ff88899f88f989ff89f9ff88ff8f898f988f8ff998f8889fff9f88f8889f8
-- </TILES>

-- <SPRITES>
-- 000:888888888888880088880055888055558880555088005500880000cc80c0cccc
-- 001:888888880088888855008888555508880555088800550088cc000088cccc0c08
-- 002:8888880088880055888055558880555088005500880000cc80c0cccc80cccc0c
-- 003:0088888855008888555508880555088800550088cc000088cccc0c08c0cccc08
-- 004:888888888888880088880055888055558880555088005500880000cc80c0cccc
-- 005:888888880088888855008888555508880555088800550088cc000088cccc0c08
-- 006:8888888888888000888805558880555588004555804444558800555088000000
-- 007:88888888000888885550888855550888555008885550008800000088cc0c0888
-- 008:8888800088880555888055558800455580444455880055508800000088800cc0
-- 009:000888885550888855550888555008885550008800000088cc0c0888cc0c0888
-- 010:8888888888888000888805558880555588004555804444558800555088000000
-- 011:88888888000888885550888855550888555008885550008800000088cc0c0888
-- 012:808888888008888880e0888880e0888880ee0000880eeeee880e0eee80e6ee0e
-- 013:88888888888888888800088880e008800ee08800ee0880e00e080ee0e6e0eee0
-- 014:8888888888880000888066668880666688060660880606608806666688066666
-- 015:8888888888888888088888080888806060880dd060880ed06088800860880608
-- 016:80cccc0c8800cc0c88800cc6888800008880cc0f8880cc0f8888000088888888
-- 017:c0cccc08c0cc00086cc00c08000f0088fff00888f00088880990888880088888
-- 018:8800cc0c88800cc68800ff0080cc0fff80cc0fff880000008880990088880008
-- 019:c0cc00886cc0088800ff0088fff0cc08fff0cc08000000880099088880008888
-- 020:80cccc0c8000cc0c80c00cc68800f00088800fff8888000f8888099088888008
-- 021:c0cccc08c0cc00886cc0088800008888f0cc0888f0cc08880000888888888888
-- 022:88800cc088880ccc8888000c8880f00088800cc088090cc08809900888800888
-- 023:cc0c0888cccc0888cc60888800088888ff000888f00990880099088880008888
-- 024:88880ccc8888000c88888800888880f08888880c8888880c8888809088888800
-- 025:cccc0888cc608888000888880f088888c0888888c00888880990888800088888
-- 026:88800cc088880ccc8888000c8880f00088800cc088090cc08809900888800888
-- 027:cc0c0888cccc0888cc60888800088888ff000888f00990880099088880008888
-- 028:80e6eeee880eee0e80eeeeee80eeeeee80e0eeee800eeeee880ee00088800888
-- 029:e6e0ee08ee000088eee08888eee08888e0e08888ee008888ee08888800888888
-- 030:80006666066000000660eeee800eeeee800eeeee0660eeee0666000080008888
-- 031:000806080660060806606608e0066088e0066088066008886660888800088888
-- 032:8888888888888000888805558880555588805555880055558800054480c00004
-- 033:8888888800088888555088885555088855550888555500884450008840000c08
-- 034:88888000888805558880555588805555880055558800054480c0000480cc0000
-- 035:00088888555088885555088855550888555500884450008840000c080000cc08
-- 036:8888888888888000888805558880555588805555880055558800054480c00004
-- 037:8888888800088888555088885555088855550888555500884450008840000c08
-- 044:8888888888888888888888808888880088880040888044048804404488040044
-- 045:8888888888888888088888884088888840008888440408884440408844004088
-- 048:80cc00008800000088800f00880cc0ff880cc0ff888000ff8888880088888888
-- 049:0000cc080000000800ff0c08ff000088ff000888ff0088880090888800088888
-- 050:880000008880ff00880fffff80c0ffff80c0ffff880000008880990088880008
-- 051:0000008800ff0888fffff088ffff0c08ffff0c08000000880099088880008888
-- 052:80cc00008000000080c0ff00880000ff888000ff888800ff8888090088888000
-- 053:0000cc080000008800f00888ff0cc088ff0cc088ff0008880088888888888888
-- 060:8090990080909999090900990909f00909099009809099998099009988008800
-- 061:009909089999090899009090900f909090099090999909089900990800880088
-- 065:8888888888888888888888888888888888888888888888888888888888888888
-- 066:8888888888888888888888888888888888888888888888888888888888888888
-- 067:8888888888888888888888888888888888888888888888888888888888888888
-- 068:8888888888888888888888888888888888888888888888888888888888888888
-- 069:8888888888888888888888888888888888888888888888888888888888888888
-- 070:8888888888888888888888888888888888888888888888888888888888888888
-- 071:8888888888888888888888888888888888888888888888888888888888888888
-- 072:8888888888888888888888888888888888888888888888888888888888888888
-- 081:8888888888888888888888888888888888888888888888888888888888888888
-- 082:8888888888888888888888888888888888888888888888888888888888888800
-- 083:8888888888888888888888888888888888888888888888888888888800000888
-- 084:8888888888888888888888888888888888888888888888888888888888888888
-- 085:8888888888888888888888888888888888888888888888888888888888888888
-- 086:8888888888888888888888888888888888888888888888888888888888888888
-- 087:8888888888888888888888888888888888888888888888888888888888888888
-- 088:8888888888888888888888888888888888888888888888888888888888888888
-- 097:88888888888800008880f0f08880dddd80000ddd006080dd066600dd0dd080dd
-- 098:888880dd088880d0f0880dd0dd080dddddd0ddddddddddd0dddddddddddddddd
-- 099:0dd0d08880080088f00f008800d0dd00ddddddddddd0ddddf0fddddddddddddd
-- 100:88888888888888888888888800888888df088888d0088888df088888d0088888
-- 101:8888888888888888888888888888888888888888888888888888888888888888
-- 102:8888888888888888888888888888888888888888888888888888888888888888
-- 103:8888888888888888888888888888888888888888888888888888888888888888
-- 104:8888888888888888888888888888888888888888888888888888888888888888
-- 113:80e080dd80e0080d80dd00dd880ddddd880ddddd880ddddd88800000880f0f0f
-- 114:dddddddddddddddddddddddddddddddddddddddddddddddd0d00000d00f0f0f0
-- 115:ddddddddddd00000dd088888dd088888dd088888d08888880888888888888888
-- 116:df08888800888888888888888888888888888888888888888888888888888888
-- 117:8888888888888888888888888888888888888888888888888888888888888888
-- 118:8888888888888888888888888888888888888888888888888888888888888888
-- 119:8888888888888888888888888888888888888888888888888888888888888888
-- 120:8888888888888888888888888888888888888888888888888888888888888888
-- 128:8888888888888888888888888888888888888888888888888888888888888888
-- 129:8888888888888888888888888888888888888888888888888888888888888888
-- 130:8888888888888888888888888888888888888888888888888888888888888888
-- 131:8888888888888888888888888888888888888888888888888888888888888888
-- 132:8888888888888888888888888888888888888888888888888888888888888888
-- 133:8888888888888888888888888888888888888888888888888888888888888888
-- 134:8888888888888888888888888888888888888888888888888888888888888888
-- 135:8888888888888888888888888888888888888888888888888888888888888888
-- 136:8888888888888888888888888888888888888888888888888888888888888888
-- 144:8888888888888888888888888888888888888888888888888888888888888888
-- 145:88888888888880888888060888880660888006608880ddd088880ed088006e08
-- 146:8888888888888888888008888806608888066608888066008880066088066666
-- 147:8888888888888888888888888888888888888888088888886088888866088888
-- 148:8888888888888888888888888888888888888888888888888888888888888888
-- 149:8888888888888888888888888888888888888888888888888888888888888888
-- 150:8888888888888888888888888888888888888888888888888888888888888888
-- 151:8888888888888888888888888888888888888888888888888888888888888888
-- 152:8888888888888888888888888888888888888888888888888888888888888888
-- 160:8888888888888888888888808888888088888880888888808888888888888888
-- 161:8006608806660888666088886660880066660066066606660666660680606606
-- 162:806666668066636600666f3666363f336666366606666066066ee00060eee088
-- 163:66088888666088886666088866660888666088886008888806608888066f0888
-- 164:8888888888888888888888888888888888888888888888888888888888888888
-- 165:8888888888888888888888888888888888888888888888888888888888888888
-- 166:8888888888888888888888888888888888888888888888888888888888888888
-- 167:8888888888888888888888888888888888888888888888888888888888888888
-- 168:8888888888888888888888888888888888888888888888888888888888888888
-- 176:8888888888888888888888888888888888888888888888888888888888888888
-- 177:880066068880666088800666888806668888006088880f6f8888800088888888
-- 178:660e0888660e008800e06f086000008808888888088888888888888888888888
-- 179:80f6088888008888888888888888888888888888888888888888888888888888
-- 180:8888888888888888888888888888888888888888888888888888888888888888
-- 181:8888888888888888888888888888888888888888888888888888888888888888
-- 182:8888888888888888888888888888888888888888888888888888888888888888
-- 183:8888888888888888888888888888888888888888888888888888888888888888
-- 184:8888888888888888888888888888888888888888888888888888888888888888
-- 192:00888888000088880ee008880eee08800eee000080eeeeee80eeeeee0eeeeeee
-- 193:8888888888000888800008880ee00888eee00888eee08888e0008888ee088888
-- 194:8888888888888888888888888888888888888888888888888888888888888888
-- 195:8888888888888888888888888888888888888888888888888888888888888888
-- 208:0feeeeee00eeeef080e66e00880e6eee888000008880e00e88800eee8880e300
-- 209:ee088888ee088888c60888886088008808800008e0000000e008800800888888
-- 210:8888888888888888888888888888888888888888888888888888888888888888
-- 211:8888888888888888888888888888888888888888888888888888888888888888
-- 224:8888000e88888880888888888888888888888888888888888888888888888888
-- 225:e088888808888888888888888888888888888888888888888888888888888888
-- 226:8888888888888888888888888888888888888888888888888888888888888888
-- 227:8888888888888888888888888888888888888888888888888888888888888888
-- 236:88888888888888880008888800e0888880ee0000880eeeee880e0eee8806ee0e
-- 237:88888888888888888800088880e008800ee08800ee0880e00e080ee0e600eee0
-- 238:88888888888888880008888800e0888880ee0000880eeeee880e0eee880eee0e
-- 239:88888888888888888800088880e008800ee08800ee0880e00e080ee0ee00eee0
-- 240:8888880088888050880005508066000006660888066608880660888800088888
-- 241:88000088806666080666666006600660000000000ff00ff080ffff0888000088
-- 242:88888888880008888066608806606608000000080ff0ff0880fff08888000888
-- 243:8888888888888888888888888888888888888888888888888888888888888888
-- 252:8806eeee80eeee0e80eeeeee80eeeeee80e0eeee800eeeee880ee00088800888
-- 253:e60eee08eee00088eee08888eee08888e0e08888ee008888ee08888800888888
-- 254:880ee0e080e6eeee80eeeeee80ee0eee80e00eee80eeeeee880ee00088800888
-- 255:ee0eee08e6e00088eee088880ee0888800e08888eee08888ee08888800888888
-- </SPRITES>

-- <MAP>
-- 000:203020203040504050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:213121213141514151000000000000002030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:203020300000000000000000000000002131000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:213121310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:2030000000000000000000000000003f3f3f3f3f3f3f3f3f3f3f3f3f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:2131000000000000000000000000003f3f3f3f3f3f3f3f3f3f3f3f3f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:2030000000000000000000000000000818000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:2131000000000000000000000000000919000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:0040500000000000000000000000000000000012121212121200003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:0041510000000000000000000000000000000013131313131300003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:4050000000000000000000000000000000000002020202020220303f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:4151000000000000000000000000000000000003030303030321313f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:0000405000000101010101010101010101010104142434445420303f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:0000415100000000000000000000000000000005152535455521313f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:0000000000000000000000000000000000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:00000000000000000000000d1d2d000000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:0000000000000000000d1d1e1e2e000000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:0000000000000000000f1e1e1e1e2d0000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:000000000000000000000f1f1f1e2e0000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:000000000000000000000000000f2f0000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:0000000000000000000000000000000000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:0000000000000000000000000000000000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:0000000000000000000000000000000000000000000000000000003f3f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <PALETTE>
-- 000:000000442434a14c300000006daa2c346524d04648757161597dce30346d4e4a4e000000d2aa99ef7d57dad45edeeed6
-- </PALETTE>

