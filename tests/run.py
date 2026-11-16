from lupa import LuaRuntime
import sys
for (H,WD,WS,AX,FILL) in [(128,0,32,False,"grass-1"),(128,0,0,False,"grass-1"),(128,0,64,False,"grass-1"),
                          (128,0,32,False,"concrete"),(1000,256,32,True,"sand-1"),(40,0,32,False,"dirt-1"),(127,0,16,False,"grass-1")]:
    L=LuaRuntime(); g=L.globals()
    g.CONTROL="../world-edge-dead-zone/control.lua"
    g.H,g.WD,g.WS,g.AX,g.FILL=H,WD,WS,AX,FILL
    L.execute(open("harness.lua").read())
