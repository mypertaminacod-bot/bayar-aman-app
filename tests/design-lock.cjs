// Approved BAYAR AMAN User/Admin design and flow are frozen.
// Changes require explicit owner approval and a deliberate baseline update.
const {execFileSync}=require('node:child_process');
const expected={
  "index.html": "6b2c469ac6d1e08715e794b9dd5631e08df04e39",
  "admin.html": "38415869cdea966800145d93db3bcdb4866af327",
  "user.js": "8a68313f2a44e994914d3fed0feb69d41b72090b",
  "admin.js": "b242f4aa3ff578a008c2ca1b84f23810331ae432",
  "route.js": "5d2d2c8f622592431ba668ab36328543ce240ccd",
  "app.css": "7c9318797cf2d994b24fbeca281fbfbc78701689",
  "icons.svg": "8addadbcd21bffd296fbeba83225a3becb39e1c2"
};
let failed=false;
for(const [file,sha] of Object.entries(expected)){
  const actual=execFileSync('git',['hash-object',file],{encoding:'utf8'}).trim();
  if(actual!==sha){console.error('LOCK VIOLATION:',file,'expected',sha,'got',actual);failed=true;}
  else console.log('LOCK OK:',file);
}
if(failed){console.error('Design/flow lock failed. Do not modify approved files without explicit owner approval.');process.exit(1);}
