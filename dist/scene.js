function officeProjection(x, y, z, angle) {
  const cos = Math.cos(angle), sin = Math.sin(angle);
  const across = (x - 300) * cos - (y - 208) * sin;
  const depth = (x - 300) * sin + (y - 208) * cos;
  return [300 + across * .78, 203 + depth * .44 - z * .79];
}

function drawOffice(ctx, agents, angle, night, frame) {
  const faces = [];
  const sin = Math.sin(angle), cos = Math.cos(angle);
  const depth = ([x,y,z]) => x*sin+y*cos+z*.557;
  const shade = (hex, multiplier) => {
    const n = parseInt(hex.slice(1),16);
    const rgb = [n>>16,(n>>8)&255,n&255].map(c=>Math.min(255,Math.round(c*multiplier)));
    return 'rgb('+rgb.join(',')+')';
  };
  const face = (vertices,color,light=1) => {
    faces.push({vertices, color:shade(color,light*(night?.65:1)), depth:vertices.reduce((sum,p)=>sum+depth(p),0)/vertices.length});
  };
  const box = (x,y,z,w,d,h,color) => {
    const a=[x,y,z+h], b=[x+w,y,z+h], c=[x+w,y+d,z+h], e=[x,y+d,z+h];
    face([a,b,c,e],color,1.08);
    face([e,c,[x+w,y+d,z],[x,y+d,z]],color,.72);
    if(sin>=0)face([b,c,[x+w,y+d,z],[x+w,y,z]],color,.86);
    else face([a,e,[x,y+d,z],[x,y,z]],color,.83);
  };
  const floor = (x,y,w,d,z,color) => face([[x,y,z],[x+w,y,z],[x+w,y+d,z],[x,y+d,z]],color);
  function paint() {
    faces.sort((a,b)=>a.depth-b.depth);
    for(const {vertices,color} of faces) {
      const projected=vertices.map(p=>officeProjection(...p,angle));
      ctx.beginPath();
      projected.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));
      ctx.closePath();ctx.fillStyle=color;ctx.fill();
    }
    faces.length=0;
  }

  const bg=ctx.createRadialGradient(300,175,15,300,175,350);
  bg.addColorStop(0,night?'#26334a':'#343f34');bg.addColorStop(1,'#151b17');
  ctx.fillStyle=bg;ctx.fillRect(0,0,600,406);
  for(let y=300;y<406;y+=12){
    ctx.strokeStyle='#a1bd9f13';ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(600,y);ctx.stroke();
  }
  box(8,57,-14,584,344,14,'#745438');
  paint();
  for(let y=59;y<397;y+=13)for(let x=10;x<588;x+=28){
    const palette=['#ad885e','#b89165','#c29b70','#b58e64','#bc956b'];
    floor(x,y,Math.min(27,590-x),12,1,palette[((x*17+y*13)^(x*y))%5]);
  }
  paint();
  box(36,93,1,265,270,3,'#b6a282');
  box(379,165,1,187,203,4,'#657e5d');
  paint();
  floor(387,173,171,187,6,'#768f6a');
  floor(43,99,251,257,5,'#c1ab8b');
  paint();

  box(8,52,0,584,8,57,'#51584a');
  box(8,50,57,584,11,4,'#767b62');
  paint();
  for(const x of [32,317]){
    box(x,60,15,124,4,38,'#303935');
    for(let i=0;i<4;i++){
      box(x+4+30*i,64,19,26,2,30,night?'#687eac':'#9ebfbb');
      box(x+7+30*i,67,39,12,1,2,night?'#a9b5d7':'#d9e2cb');
    }
    box(x-3,60,14,130,10,4,'#928770');
  }
  for(const x of [192,492]){
    box(x,61,0,66,13,48,'#6f4f39');
    for(const z of [3,23]){
      for(let i=0;i<9;i++) box(x+3+i*7,73,z+3,5,7,8+(i*7%11),['#aa7657','#92a178','#cdad79'][i%3]);
      box(x,62,z,66,21,3,'#876044');
    }
  }
  function plant(x,y) {
    box(x-7,y-7,0,14,14,11,'#a36648');
    box(x-2,y-2,11,4,4,16,'#64784e');
    box(x-10,y-5,20,10,21,11,'#6f9058');
    box(x-5,y-10,25,13,19,12,'#799962');
  }
  for(const [x,y] of [[21,82],[350,177],[575,135],[574,367],[36,374]])plant(x,y);
  function sofa(x,y,w) {
    box(x,y,4,w,31,10,'#455b45');box(x,y,14,w,8,20,'#526d53');
    box(x,y+8,14,7,23,12,'#536e53');box(x+w-7,y+8,14,7,23,12,'#536e53');
    box(x+8,y+9,14,w-16,20,6,'#8b9d78');
    box(x+13,y+10,20,15,10,5,'#c69368');
  }
  sofa(412,181,115);sofa(420,319,104);
  box(451,249,5,47,22,12,'#624b38');box(447,246,17,55,29,5,'#d0b68e');
  box(473,254,22,7,7,6,'#e7d7b3');
  box(449,75,0,106,29,23,'#7b5841');box(447,73,23,110,32,4,'#bc966c');
  box(476,77,27,17,15,17,'#444941');box(480,89,31,7,7,5,'#dac39c');
  box(329,311,0,19,29,31,'#444c41');

  for(const {x,y,state} of agents){
    for(const lx of [x-38,x+32])for(const ly of [y-9,y+7])box(lx,ly,4,5,5,17,'#604533');
    box(x-42,y-13,21,84,26,5,'#9a6948');
    box(x-10,y-10,26,20,7,2,'#666d5e');
    box(x-3,y-11,28,6,4,6,'#7c8374');
    box(x-17,y-13,32,34,5,18,'#363d38');
    box(x-14,y-8,34,28,1,14,state==='resting'?'#33413c':'#547d68');
    if(state!=='resting')for(let i=0;i<3;i++)box(x-11+i*2,y-7,45-i*4,8+(frame+i*4)%10,1,1,'#badea1');
    box(x-11,y+2,26,22,6,2,'#444640');box(x+28,y-1,26,5,5,5,'#ead6ae');
    box(x-9,y+16,4,18,13,8,'#464c44');
    box(x-9,y+27,11,18,4,13,'#414741');
  }
  const skin=['#e2a77b','#da9a70','#b9825f','#e9b389','#aa7154'];
  const hair=['#49372c','#6f4533','#292a2a','#594235','#322820'];
  agents.forEach((a,i)=>{
    if(a.vacant)return;
    const x=a.px,y=a.py;
    box(x-6,y-4,4,5,8,8,'#343b3a');box(x+1,y-4,4,5,8,8,'#343b3a');
    box(x-7,y-5,12,14,10,13,a.shirt);
    const armZ=a.state==='working' && frame%8<4?16:14;
    box(x-10,y-3,armZ,3,6,7,skin[i]);box(x+7,y-3,28-armZ,3,6,7,skin[i]);
    box(x-6,y-5,25,12,10,11,skin[i]);box(x-7,y-6,34,14,12,5,hair[i]);
    box(x-6,y+4,32,12,2,4,hair[i]);
  });
  paint();
}
