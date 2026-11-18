const $ = (selector) => document.querySelector(selector);
const canvas = $('#floor');
const ctx = canvas.getContext('2d');
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const agents = [
  { name:'Codex', icon:'⌘', color:'#bde496', shirt:'#607c45', x:102, y:132, state:'working', task:'Building the settings page', log:'editing  settings.tsx' },
  { name:'Claude', icon:'✳', color:'#e9a581', shirt:'#ba7453', x:225, y:132, state:'waiting', task:'Updating the data model', question:'Should the activity feed show only completed tasks, or include tasks still in progress?', log:'paused  awaiting input' },
  { name:'Cursor', icon:'↗', color:'#adbaec', shirt:'#596c96', x:102, y:221, state:'working', task:'Refining the navigation', log:'editing  navigation.tsx' },
  { name:'Copilot', icon:'◉', color:'#d8bbed', shirt:'#8d679b', x:225, y:221, state:'working', task:'Checking form validation', log:'running  form checks' },
  { name:'Gemini', icon:'✦', color:'#a6d9dc', shirt:'#528687', x:163, y:310, state:'resting', task:'Finished updating the docs', log:'done     README.md' },
];
let selected = 0;
const macBridge = window.webkit?.messageHandlers;
const windowsBridge = window.chrome?.webview;
const native = Boolean(macBridge?.officeReady || windowsBridge);
function sendToDesktop(type,id) {
  if(macBridge)macBridge[type].postMessage(id ?? 'ready');
  else windowsBridge?.postMessage({type,id});
}
const live = native;
let liveCount = 0;
let workingSessions = [];
let visible = !native;
let animation;
let night = false;
let spatial = !native;
let angle = -.44;
const statuses = {working:'Working', waiting:'Needs input', resting:'On break'};
const markerButtons = [];
const agentButtons = [];
const position = (agent, index) => agent.state === 'resting'
  ? [458 + index % 3 * 34, 253 + Math.floor(index / 3) * 42]
  : [agent.x, agent.y + 20];

function rect(x,y,w,h,color) {
  ctx.fillStyle=color;
  ctx.fillRect(Math.round(x),Math.round(y),w,h);
}
function plant(x,y,big=false) {
  if (big) { ctx.save(); ctx.translate(x,y); ctx.scale(1.45,1.45); x=0; y=0; }
  rect(x-10,y+6,23,5,'#312f2b45');
  rect(x-7,y-3,14,13,'#915d45');rect(x-7,y-4,14,3,'#c07b59');rect(x-4,y+9,8,3,'#764634');
  rect(x-1,y-20,2,18,'#41563b');rect(x-10,y-17,8,6,'#506d43');rect(x+1,y-21,8,8,'#658453');
  rect(x-11,y-20,7,4,'#78945b');rect(x-4,y-25,7,7,'#729258');rect(x+3,y-12,9,5,'#547746');
  if (big) ctx.restore();
}
function windowBay(x,w) {
  rect(x-4,10,w+8,44,'#343738');rect(x,13,w,35,'#6b8a8d');
  for(let j=0;j<4;j++){
    const px=x+j*w/4;
    rect(px+2,15,w/4-4,28,night?'#303e58':'#a6c3bf');
    rect(px+2,32,w/4-4,11,night?'#414866':'#8faa9d');
    rect(px+5,21,7,3,night?'#66677d':'#dce0bb');
  }
  rect(x-5,48,w+10,4,'#8d8c76');rect(x-3,52,w+6,4,'#252d2a');
}
function shelf(x,y) {
  rect(x+4,y+4,68,46,'#302e29');rect(x,y,68,46,'#78553c');rect(x+3,y+3,62,37,'#4e3c31');
  for(let row=0;row<2;row++)for(let j=0;j<11;j++){
    const h=8+(j*5+row*2)%8;
    rect(x+5+j*5,y+19+row*19-h,4,h,['#a98b65','#788765','#bd765b','#d1b696','#6b757f'][j%5]);
  }
  rect(x,y+19,68,3,'#9a7250');rect(x,y+38,68,4,'#9a7250');
}
function sofa(x,y,w) {
  rect(x+3,y+18,w,12,'#28352895');rect(x+4,y+23,4,8,'#283129');rect(x+w-8,y+23,4,8,'#283129');
  rect(x,y,w,24,'#35483a');rect(x+4,y+3,w-8,8,'#526a51');
  rect(x+6,y+12,w/2-7,9,'#718566');rect(x+w/2+1,y+12,w/2-7,9,'#718566');
  rect(x,y+9,6,15,'#476147');rect(x+w-6,y+9,6,15,'#476147');
  rect(x+10,y+8,10,8,'#bc8b5f');rect(x+w-21,y+8,10,8,'#a8ac7a');
}
function background() {
  rect(0,0,600,406,'#423d35');
  for(let y=58;y<400;y+=12)for(let x=7;x<594;x+=29){
    const n=((x*13+y*17)^(x*y))>>>0;
    rect(x,y,28,11,['#a58561','#ad8d68','#b0916d','#a98a66','#b69873'][n%5]);
    if(n%3===0)rect(x+4,y+4,10+n%9,1,'#e9c28b22');
  }
  rect(7,58,586,7,'#54463688');rect(0,0,600,58,'#494841');rect(0,0,600,5,'#282f2b');
  rect(0,56,600,4,'#635443');
  windowBay(25,140);shelf(189,9);windowBay(311,140);shelf(495,9);
  rect(274,14,19,19,'#292e2a');rect(276,16,15,15,'#c8bea0');
  rect(283,18,1,7,'#595b49');rect(284,24,4,1,'#595b49');
  if(!night){
    ctx.fillStyle='#f9dfa21e';
    ctx.beginPath();[[31,59],[163,59],[227,220],[90,220]].forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.fill();
    ctx.beginPath();[[318,59],[448,59],[526,209],[392,209]].forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.fill();
  }
  rect(38,100,266,266,'#433f3728');rect(35,97,266,266,'#b29c81');
  for(let y=101;y<361;y+=6)for(let x=39;x<299;x+=9)rect(x,y,7,4,(x+y)%4?'#b7a084':'#bba588');
  rect(35,97,266,2,'#d0b599');rect(35,360,266,3,'#8b7259');
  rect(382,170,186,205,'#343c2d50');rect(377,165,188,206,'#566c50');
  rect(382,170,178,196,'#809474');rect(386,174,170,188,'#697e60');
  for(let y=175;y<360;y+=5)for(let x=388;x<553;x+=10)rect(x,y,6,2,(x+y)%3?'#6d8263':'#76896a');
  sofa(411,184,119);sofa(420,314,102);
  rect(448,271,58,12,'#353e3055');rect(457,265,40,11,'#654e3d');rect(448,251,58,16,'#80664c');
  rect(452,247,50,21,'#c5ad88');rect(448,252,58,10,'#c5ad88');rect(466,254,12,7,'#7c8d70');rect(487,253,5,5,'#f1dbb4');
  rect(450,80,105,36,'#4b4238');rect(449,77,107,13,'#b69575');rect(452,91,101,20,'#7f614e');
  for(let x=454;x<551;x+=24){rect(x,96,20,11,'#8d7058');rect(x+7,98,6,1,'#d0aa80');}
  rect(478,70,18,15,'#444643');rect(480,72,14,5,'#777c72');rect(483,80,6,4,'#d9bc90');
  rect(518,76,5,7,'#ede0c5');rect(527,76,5,7,'#baa384');rect(539,78,11,4,'#6b6e52');
  plant(20,76);plant(575,137,true);plant(350,183,true);plant(570,369);plant(38,370);
  rect(329,314,19,51,'#3b3d36');rect(331,316,15,47,'#4b5145');
  for(let y=320;y<362;y+=7){rect(333,y,11,4,'#272f29');rect(341,y+1,2,1,'#a7cb87');}
  rect(0,60,6,345,'#5f5244');rect(594,60,6,345,'#5f5244');rect(0,399,600,7,'#68523e');
}
function desk(agent, frame) {
  const {x,y,state}=agent;
  rect(x-42,y-2,87,25,'#3e302b50');rect(x-39,y+12,5,13,'#5b4334');rect(x+34,y+12,5,13,'#5b4334');
  rect(x-42,y-8,84,25,'#684936');rect(x-42,y-12,84,25,'#a17253');rect(x-40,y-10,80,1,'#c09169');
  rect(x-37,y+7,72,1,'#8f604a');rect(x-39,y+12,78,1,'#805640');
  rect(x-4,y-11,8,9,'#656d62');rect(x-10,y-4,20,3,'#b6b8a0');
  rect(x-18,y-32,36,23,'#3b433b');rect(x-16,y-31,32,19,'#a8b2a1');rect(x-14,y-29,28,15,'#232e2b');
  if(state!=='resting') {
    for(let row=0;row<4;row++){
      const length=6+(row*7+Math.floor(frame/7))%15;
      rect(x-11+row%2*3,y-27+row*3,length,1,row===0?'#ceb181':'#96bb9d');
    }
  }
  rect(x-35,y-3,9,7,'#ead5ad');rect(x-32,y-2,4,1,'#af9b7a');
  rect(x+27,y-3,6,7,'#ded2b7');rect(x+33,y-1,2,3,'#ded2b7');
  rect(x-10,y+3,20,6,'#4a4640');for(let k=0;k<8;k++)rect(x-8+k*2,y+5,1,2,'#8d9080');
  rect(x-10,y+19,20,13,'#393b35');rect(x-2,y+30,4,7,'#333731');rect(x-9,y+35,18,2,'#333731');
}
function person(x,y,agent,frame,seated,index) {
  const skin=['#e2a77b','#da9a70','#b9825f','#e9b389','#aa7154'][index];
  const hair=['#49372c','#6f4533','#292a2a','#594235','#322820'][index];
  const wave=agent.state==='working' && frame%8<4 ? 1 : 0;
  rect(x-10,y+10,20,5,'#2d302a48');
  rect(x-6,y+7,5,6,'#333b3a');rect(x+1,y+7,5,6,'#333b3a');
  rect(x-8,y-4,16,13,agent.shirt);rect(x-9,y-3+wave,3,7,skin);rect(x+7,y-3-wave,3,7,skin);
  rect(x-6,y-15,12,11,skin);rect(x-7,y-17,14,5,hair);rect(x-7,y-13,3,5,hair);rect(x+4,y-14,3,5,hair);
  if(!seated){rect(x-3,y-10,1,2,'#362b25');rect(x+3,y-10,1,2,'#362b25');}
}
agents.forEach((agent,index) => {
  for(const [className,container,buttons] of [['marker','#markers',markerButtons],['agent','#agents',agentButtons]]){
    const button=document.createElement('button');
    button.type='button';
    button.className=className;
    button.addEventListener('click',()=>{
      if (live && className==='marker') {
        const session=workingSessions[index];
        if(session && (session.provider==='Codex'||session.directory))sendToDesktop('openSession',session.id);
      } else select(index);
    });
    $(container).append(button);
    buttons.push(button);
  }
  $('#assignee').add(new Option(agent.name,index));
  [agent.px,agent.py]=position(agent,index);
});

let lastFrame=-1;
function draw(time=0){
  animation=undefined;
  if (!visible) return;
  const frame=reduceMotion?0:Math.floor(time/110);
  if(frame!==lastFrame || reduceMotion){
    lastFrame=frame;
    const occupants = live ? agents.map((agent,index) => ({
      ...agent, px:agent.x, py:agent.y+20, state:workingSessions[index]?.state||'resting',
      vacant:index>=workingSessions.length
    })) : agents;

    if (!spatial) {
      background();
      occupants.forEach(agent=>desk(agent,frame));
    }
    occupants.forEach((agent,index)=>{
      let atDesk=live;
      if(!live){
        const [x,y]=position(agent,index);
        const distance=Math.hypot(x-agent.px,y-agent.py);
        const step=reduceMotion?1:Math.min(1,24/(distance||1));
        agent.px+=(x-agent.px)*step;
        agent.py+=(y-agent.py)*step;
        atDesk=agent.state!=='resting'&&distance<3;
      }
      if(!spatial && !agent.vacant)person(agent.px,agent.py,agent,frame,atDesk,index);
      const [mx,my] = spatial ? officeProjection(agent.px,agent.py,48,angle)
        : [agent.px,agent.py-(agent.state==='resting'?27:61)];
      markerButtons[index].style.left=(mx/6)+'%';
      markerButtons[index].style.top=(my/4.06)+'%';
    });
    if(spatial)drawOffice(ctx,occupants,angle,night,frame);
    else if(night) {
      rect(0,0,600,406,'#18243d70');
      occupants.filter(a=>a.state!=='resting').forEach(a=>rect(a.x-14,a.y-29,28,15,'#a8eace35'));
    }
  }
  if(!reduceMotion && (!live || workingSessions.length)) animation=requestAnimationFrame(draw);
}

function refresh(){
  agents.forEach((agent,index)=>{
    const marker=markerButtons[index];
    const row=agentButtons[index];
    marker.innerHTML='<i class="'+agent.state+'"></i><span>'+agent.name+'</span>';
    marker.setAttribute('aria-label',agent.name+' · '+statuses[agent.state]);
    row.innerHTML='<span class="avatar" style="background:'+agent.color+'" aria-hidden="true">'+agent.icon+'</span><span><strong>'+agent.name+'</strong><small>'+statuses[agent.state]+'</small></span><i class="'+agent.state+'"></i>';
    [marker,row].forEach(b=>b.setAttribute('aria-pressed',index===selected));
  });
  $('#stats').textContent=agents.filter(a=>a.state==='working').length+' working · '+agents.filter(a=>a.state==='waiting').length+' needs input';
  const agent=agents[selected];
  $('#details').innerHTML='<div class="eyebrow"><i class="'+agent.state+'"></i>'+statuses[agent.state]+'</div><h2>'+agent.name+'</h2><p id="current-task"></p><pre></pre>'+
    (agent.state==='waiting'?'<form id="reply"><label>Your reply<input required maxlength="160" placeholder="Type a reply"></label><button class="primary">Send reply</button></form>':
      '<button class="secondary" id="agent-action">'+(agent.state==='working'?'Complete task':'Assign a task')+'</button>');
  $('#current-task').textContent=agent.state==='waiting'?agent.question:agent.task;
  $('#details pre').textContent=agent.log;
  $('#reply')?.addEventListener('submit',event=>{
    event.preventDefault();
    const reply=event.currentTarget.querySelector('input').value.trim();
    if(!reply)return;
    agent.state='working';agent.log='reply    '+reply;refresh();$('#agent-action').focus();
  });
  $('#agent-action')?.addEventListener('click',()=>{
    if(agent.state==='resting')return openTask();
    agent.state='resting';agent.log='done     taking a break';refresh();$('#agent-action').focus();
  });
  if(reduceMotion)draw();
}
function select(index){selected=index;refresh();}
function openTask(){
  $('#assignee').value=selected;
  $('#task').value='';
  $('#dialog').showModal();
  $('#task').focus();
}
$('#theme').addEventListener('click',event=>{
  night=!night;
  event.currentTarget.setAttribute('aria-pressed',night);
  event.currentTarget.textContent=night?'☀ Day mode':'☾ Night mode';
  if(reduceMotion || (live && !workingSessions.length))draw();
});
$('#new-task').addEventListener('click',openTask);
$('#close').addEventListener('click',()=>$('#dialog').close());
$('#task-form').addEventListener('submit',event=>{
  event.preventDefault();
  const task=$('#task').value.trim();
  if(!task){$('#task').focus();return;}
  selected=Number($('#assignee').value);
  Object.assign(agents[selected],{state:'working',task,log:'started  '+task});
  $('#dialog').close();
  refresh();
});
refresh();
if(!reduceMotion && visible)animation=requestAnimationFrame(draw);

$('#view').addEventListener('click',event=>{
  spatial=!spatial;
  $('#map').classList.toggle('spatial',spatial);
  event.currentTarget.textContent=spatial?'3D':'2D';
  event.currentTarget.setAttribute('aria-pressed',spatial);
  lastFrame=-1;
  if(reduceMotion || (live && !workingSessions.length))draw();
});
let dragStart;
canvas.addEventListener('pointerdown',event=>{
  if(!spatial)return;
  dragStart={x:event.clientX,angle};
  canvas.setPointerCapture(event.pointerId);
});
canvas.addEventListener('pointermove',event=>{
  if(!dragStart)return;
  angle=Math.max(-.87,Math.min(.83,dragStart.angle+(event.clientX-dragStart.x)*.005));
  lastFrame=-1;
  if(reduceMotion || (live && !workingSessions.length))draw();
});
for(const type of ['pointerup','lostpointercapture'])canvas.addEventListener(type,()=>{dragStart=undefined;});

if (native) {
  document.body.classList.add('native','live');
  $('#map').classList.remove('spatial');
  markerButtons.forEach(button=>{button.hidden=true;});
  const summary=document.createElement('div');
  summary.className='live-status';
  summary.setAttribute('role','status');
  summary.textContent='Looking for local agents…';
  document.querySelector('.intro').after(summary);
  document.querySelector('h1').textContent='Live office';

  const section=document.createElement('section');
  section.className='card live-sessions';
  section.innerHTML='<div class="panel-head"><span>Working now</span></div><ul></ul>';
  section.setAttribute('aria-label','Working agents');
  document.querySelector('.layout').append(section);
  const list=section.querySelector('ul');
  let lastView='';
  const statusText=session=>session.action||'Working on this task';

  function renderSessions(sessions) {
    list.replaceChildren();
    if(!sessions.length) {
      const empty=document.createElement('li');
      empty.className='session-empty';
      empty.textContent='No agents are working right now.';
      list.append(empty);
    }
    for(const session of sessions) {
      const row=document.createElement('li');
      const info=document.createElement('div');
      const provider=document.createElement('strong');
      provider.textContent=session.provider;
      const task=document.createElement('div');
      task.className='session-task';
      task.textContent=session.title;
      const detail=document.createElement('small');
      detail.textContent=[statusText(session),session.project].filter(Boolean).join(' · ');
      info.append(provider,task,detail);
      const button=document.createElement('button');
      button.className='secondary';
      button.textContent=session.provider==='Codex'?'Open in Codex':'Open folder';
      button.setAttribute('aria-label',button.textContent+' · '+session.provider+' · '+session.title);
      button.addEventListener('click',()=>sendToDesktop('openSession',session.id));
      const signal=document.createElement('i');
      signal.className='working';
      row.append(signal,info);
      if(session.provider==='Codex'||session.directory)row.append(button);
      list.append(row);
    }
  }

  function redraw() {
    if(animation!==undefined)cancelAnimationFrame(animation);
    lastFrame=-1;
    draw(performance.now());
  }

  window.showLocalActivity=({sessions,sources})=>{
    const working=sessions.filter(session=>session.state==='working');
    const view=JSON.stringify([sources,working.map(({id,provider,project,title,action,directory})=>[id,provider,project,title,action,directory])]);
    if(view===lastView)return;
    lastView=view;
    const focused=document.activeElement?.getAttribute('aria-label');
    workingSessions=working;
    liveCount=working.length;
    markerButtons.forEach((marker,index)=>{
      const session=workingSessions[index];
      marker.hidden=!session;
      if(!session)return;
      const signal=document.createElement('i');
      signal.className='working';
      marker.replaceChildren(signal,session.provider);
      marker.title=session.title+' · '+statusText(session);
      marker.removeAttribute('aria-pressed');
      marker.setAttribute('aria-label',session.provider+' · '+session.title+' · '+statusText(session));
      marker.disabled=session.provider!=='Codex' && !session.directory;
    });
    summary.hidden=!liveCount && Boolean(sources.length);
    summary.textContent=liveCount?liveCount+' working':sources.length?'No agents are working right now':'No local agent session folders found';
    $('#stats').textContent=liveCount>5?'Showing 5 of '+liveCount+' working':'';
    renderSessions(working);
    if(focused) [...list.querySelectorAll('button')].find(button=>button.getAttribute('aria-label')===focused)?.focus();
    redraw();
  };
  window.showSessionOpenError=()=>{summary.textContent='Could not open this session or project folder.';};
  window.setOfficeVisibility=(show)=>{
    visible=show;
    redraw();
  };
  sendToDesktop('officeReady');
}
