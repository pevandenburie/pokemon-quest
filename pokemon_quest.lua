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

local SOLID_TILES_FROM=2
local SOLID_TILES_TO=87

-- global variables
local t=0	-- global time, used in TIC() method
local cam={x=0,y=0}
local mobs={}
local firstRun=true

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
	trace(indx)
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
	
	function s.Move(dx,dy)
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
			if not s.damaged then s.curAnim=s.anims.walk end
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
	
	s.anims={
		idle=Anim(60,{256,258}),
		walk=Anim(15,{260,262}),
	}
	
	-- store the super method
	local supMove=s.Move
	
	function s.Move(dx,dy)
		-- call super.move
		supMove(dx,dy)
		
		-- flip
		if dx~=0 then s.flip=dx<0 and 1 or 0 end
	end
	
	function s.Update(time)		
		s.dx=0
		s.dy=0
		
		-- default: idle
		s.curAnim=s.anims.idle

		-- manage the user input
		-- arrows [0,1,2,3].......movement
		-- z [4].........................attack
		-- x [5].........................healing
		if btn(0) then s.Move(0,-1) end
		if btn(1) then s.Move(0,1) end
		if btn(2) then s.Move(-1,0) end
		if btn(3) then s.Move(1,0)	end
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

-- init
local p1

local function Init()
	-- detect if run for the fisrt time
	if not firstRun then return end
	firstRun=false
	
	-- clear tables
	mobs={}
	-- animTiles={}
	-- traps={}
	-- bullets={}
	
	-- create player
	p1=Player(8*CELL,6*CELL)
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
		
	
	-- player
	p1.Update(t)
	
	------------- DISPLAY -------------
	-- player
	p1.Display(t)

	-- increment global time
	t=t+1
end
-- <TILES>
-- 000:4444444444444444444444444445444444444444444445444444444444444444
-- 002:4444444445444044444005044405555040550055050055550040550044055002
-- 003:4444444444004444405504440555500455555504000555500440055004544000
-- 004:4444444445444444444400004400777744077a77440777a740a7777740a77777
-- 005:444444444445444400044445770004447f7700447ff7704477ff770477777704
-- 016:4444444412441244122212221111111112441244124412441244124444444444
-- 018:4405040245004402444444004444444044455444444444444544444544444445
-- 019:0444444420444444220444542204444402204444022045440525444455555444
-- 020:40a7a77740a7aa77400a7777440055a74445555a445455554444444444444444
-- 021:7777770477aa770477777004757700445aa50444555454444444444444444454
-- 032:0000000001111111010000000010000000010000000010000000010000000010
-- 033:0000000011111111000000000000000000000000000000000000000000000000
-- 034:0000000011111111000000000000000000000000000000000000000000000000
-- 035:0000000011111111000000000000000000000000000000000000000000000000
-- 036:0000000011111111000000000000000000000000000000000000000000000000
-- 037:0000000011111110000000100000010000001000000100000010000001000000
-- 048:0000000100000001000000110000001100000111000001110000111100001111
-- 049:1111111111111111111111111111111111111111111111111111111111111111
-- 050:1111111111111111111111111111111111111111111111111111111111111111
-- 051:1111111111111111111111111111111111111111111111111111111111111111
-- 052:1111111111111111111111111111111111111111111111111111111111111111
-- 053:1000000010000000110000001100000011100000111000001111000011110000
-- 064:0001111100011111001111110011111101111111011111110111111100000000
-- 065:1111111111111111111111111111111111111111111111111111111100000000
-- 066:1111111111111111111111111111111111111111111111111111111100000000
-- 067:1111111111111111111111111111111111111111111111111111111100000000
-- 068:1111111111111111111111111111111111111111111111111111111100000000
-- 069:1111100011111000111111001111110011111110111111101111111000000000
-- 080:0a770eee0aaa0eee0000ee000a70ee090aa0ee09000eee0f0a70ee090aa0ee00
-- 081:eeeeeee0eeeeeee0000000e09f99f0e0f99f90e099f990e09f9990e0000000e0
-- 082:a7777777aaaaaaaa00000000a7012212a7012212a7012212a7012212a7012212
-- 083:77777777aaaaaaa700000000212220a7212220a7212220a7212220a7212220a7
-- 084:0eeeeeee0eeeeeee0e0000000e099f990e09f99f0e0f99f90e099f990e000000
-- 085:eee077a0eee0aaa000ee0000f0ee07a090ee0aa090eee00090ee07a000ee0aa0
-- 096:000eeeee0a70eeee0aa0eeee0000eeee0a770eee0aaa0eee0000000044444444
-- 097:eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee00000000044444444
-- 098:a7012212a7012212a7012212a7012212a7012212a7012212a701221200000000
-- 099:212a20a721a2a0a7212a20a7212220a7212220a7212220a7212220a700000000
-- 100:0eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0eeeeeee0000000044444444
-- 101:eeeee000eeee07a0eeee0aa0eeee0000eee077a0eee0aaa00000000044444444
-- </TILES>

-- <SPRITES>
-- 000:88888800888888008888880c8888888c8888888c88888fff8888ccf68888c8ff
-- 001:008888880c888888ccc88888cc88c888c888c888fff8c8886f8c8888ff888888
-- 002:88888800888888008888880c8888888c8888888c888888ff88888ff68888ccff
-- 003:008888880c888888ccc88888cc888888c888c888ff88c8886ff8c888ff8c8888
-- 004:88888800888888008888880c8888888c8888888c88888fff8888ccf68888c8ff
-- 005:008888880c888888ccc88888cc88c888c888c888fff8c8886f8c8888ff888888
-- 006:88888800888888008888880c8888888c8888888c888888ff88888ff68888ccff
-- 007:008888880c888888ccc88888cc888888c888c888ff88c8886ff8c888ff8c8888
-- 016:8888c8ff8888c899888888998888889988888999888889988888899888888000
-- 017:ff88888899888888999888888999888889998888889988888899888888000888
-- 018:8888c8ff8888c8998888c8998888889988888999888889988888899888888000
-- 019:ff88888899888888999888888999888889998888889988888899888888000888
-- 020:8888c8ff8888c899888888998888889988809999888099988880888888888888
-- 021:ff88888899888888999888888999888889998888889988888899888888000888
-- 022:8888c8ff8888c8998888c8998888889988888999888899988888098888888008
-- 023:ff88888899888888999988888999988888899888888000888888888888888888
-- 032:8888888888888888888888888888888888888888888888888888888888888888
-- 033:8888888888888888888888888888888888888888888888888888888888888888
-- 034:8888888888888888888888888888888888888888888888888888888888888888
-- 035:8888888888888888888888888888888888888888888888888888888888888888
-- 036:8888888888888888888888888888888888888888888888888888888888888888
-- 037:8888888888888888888888888888888888888888888888888888888888888888
-- 048:8888888888888888888888888888888888888888888888888888888888888888
-- 049:88888888888880888888060888880660888006608880ddd088880ed088006e08
-- 050:8888888888888888888008888806608888066608888066008880066088066666
-- 051:8888888888888888888888888888888888888888088888886088888866088888
-- 052:8888888888888888888888888888888888888888888888888888888888888888
-- 053:8888888888888888888888888888888888888888888888888888888888888888
-- 064:8888888888888888888888808888888088888880888888808888888888888888
-- 065:8006608806660888666088886660880066660066066606660666660680606606
-- 066:806666668066636600666f3666363f336666366606666066066ee00060eee088
-- 067:66088888666088886666088866660888666088886008888806608888066f0888
-- 080:8888888888888888888888888888888888888888888888888888888888888888
-- 081:880066068880666088800666888806668888006088880f6f8888800088888888
-- 082:660e0888660e008800e06f086000008808888888088888888888888888888888
-- 083:80f6088888008888888888888888888888888888888888888888888888888888
-- 096:00888888000088880ee008880eee08800eee000080eeeeee80eeeeee0eeeeeee
-- 097:8888888888000888800008880ee00888eee00888eee08888e0008888ee088888
-- 098:8888888888888888888888888888888888888888888888888888888888888888
-- 099:8888888888888888888888888888888888888888888888888888888888888888
-- 112:0feeeeee00eeeef080e66e00880e6eee888000008880e00e88800eee8880e300
-- 113:ee088888ee088888c60888886088008808800008e0000000e008800800888888
-- 114:8888888888888888888888888888888888888888888888888888888888888888
-- 115:8888888888888888888888888888888888888888888888888888888888888888
-- 128:8888000e88888880888888888888888888888888888888888888888888888888
-- 129:e088888808888888888888888888888888888888888888888888888888888888
-- 130:8888888888888888888888888888888888888888888888888888888888888888
-- 131:8888888888888888888888888888888888888888888888888888888888888888
-- 144:8888888888888888888888888888888888888888888888888888888888888888
-- 145:8888888888888888888888888888888888888888888888888888888888888888
-- 146:8888888888888888888888888888888888888888888888888888888888888888
-- 147:8888888888888888888888888888888888888888888888888888888888888888
-- </SPRITES>

-- <MAP>
-- 000:203020203040504050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:213121213141514151000000000000002030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:203020300000000000000000000000002131000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:213121310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:213100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:203000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:213100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:004050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:004151000000000000000000000000000000000212223242520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:405000000000000000000000000000000000000313233343532030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:415100000000000000000000000000000000000414243444542131000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:000040500000010101010101010101010101010515253545552030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:000041510000000000000000000000000000000616263646562131000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <PALETTE>
-- 000:000000442434a14c300000006daa2c346524d04648757161597dce30346d4e4a4e29366fd2aa99ef7d57dad45edeeed6
-- </PALETTE>

