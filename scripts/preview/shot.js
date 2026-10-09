const {chromium}=require('/opt/node-tools/node_modules/playwright');
(async()=>{
 const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium',args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
 const pg=await b.newPage({viewport:{width:1500,height:900}});
 pg.on('console',m=>console.log('console:',m.text()));pg.on('pageerror',e=>console.log('pageerror:',e));
 await pg.goto('file://'+__dirname+'/index.html');
 await pg.evaluate(()=>{
  clearAll();
  // Rows: light direction sweep (glints re-catch as the mouse moves). Columns: rest / stretched / long taut.
  // Facet amount follows the app's crystallize rule: base*0.55 * ((1-cry) + cry*(0.3+0.9*stretchT)), cry=.7.
  const W=500,H=300, base=0.55, cry=0.7;
  const st=x=>{const t=Math.min(1,Math.max(0,x));return t*t*(3-2*t)};
  const sc=[[[170,150],[210,140],0],[[130,150],[300,120],10],[[70,170],[440,90],-26]];
  const lights=[[-.45,.8],[.6,.6],[-.2,-.7]];
  lights.forEach((ld,r)=>sc.forEach((s,c)=>{
    const chord=Math.hypot(s[1][0]-s[0][0],s[1][1]-s[0][1]);
    const f=Math.min(1,base*((1-cry)+cry*(.3+.9*st((chord-40)/200))));
    drawScene(c*W,(2-r)*H,W,H,s[0],s[1],s[2],f,22,ld);}));
 });
 await pg.screenshot({path:__dirname+'/out.png'});
 await b.close();
})();
