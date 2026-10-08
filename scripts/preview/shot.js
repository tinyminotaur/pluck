const {chromium}=require('/opt/node-tools/node_modules/playwright');
(async()=>{
 const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium',args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
 const pg=await b.newPage({viewport:{width:1500,height:900}});
 pg.on('console',m=>console.log('console:',m.text()));pg.on('pageerror',e=>console.log('pageerror:',e));
 await pg.goto('file://'+__dirname+'/index.html');
 await pg.evaluate(()=>{
  clearAll();
  const facets=[0,0.55,1.0], W=500,H=300;
  const sc=[ // pin, head, sag
   [[170,150],[210,140],0],
   [[130,150],[300,120],10],
   [[70,170],[440,90],-26]];
  facets.forEach((f,r)=>sc.forEach((s,c)=>drawScene(c*W,(2-r)*H,W,H,[s[0][0]+c*W*0,s[0][1]],[s[1][0],s[1][1]],s[2],f,22,[-.45,.8])));
 });
 await pg.screenshot({path:__dirname+'/out.png'});
 await b.close();
})();
