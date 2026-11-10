import {useEffect,useState,type FormEvent} from 'react';
import {createRoot} from 'react-dom/client';
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/700.css';
import './style.css';
interface SpaceBody{title:string;address:string;hourlyRate:number;active:boolean}
interface Space{id:string;state:string;body:SpaceBody}
interface Reservation{id:string;code:string;start_time:string;end_time:string;status:string;amount:number}
interface Payment{id:string;amount:number;status:string;refunded_amount:number;created_at:string;provider:string}
interface SpaceCounts{total:number;active:number}
interface ReservationCounts{pending:number;active:number;confirmed:number;completed:number}
interface Dashboard{observedAt:string;truncated:boolean;spaces:SpaceCounts;reservations:ReservationCounts;income:number;byMonth:Record<string,number>;upcoming:Reservation[];transactions:Payment[];inventory:Space[];occupiedSpaces:number}
const base=import.meta.env.VITE_API_URL??'http://localhost:3000';
const currency=new Intl.NumberFormat('es-PE',{style:'currency',currency:'PEN'});
const date=new Intl.DateTimeFormat('es-PE',{timeZone:'America/Lima',dateStyle:'medium',timeStyle:'short'});
const money=(n:number)=>currency.format(n/100);
function App(){
 const[token,setToken]=useState<string|null>(null),[data,setData]=useState<Dashboard|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(false),[refresh,setRefresh]=useState(0),[period,setPeriod]=useState('');
 useEffect(()=>{
  if(!token)return;const abort=new AbortController();let ignore=false;
  setLoading(true);setError('');
  fetch(`${base}/owner/dashboard`,{headers:{Authorization:`Bearer ${token}`},signal:abort.signal}).then(async r=>{
   if(r.status===401){setToken(null);throw new Error('La sesión venció. Inicia sesión nuevamente.');}
   if(!r.ok)throw new Error('No se pudo consultar la actividad. No se muestran cifras estimadas.');
   return r.json() as Promise<Dashboard>;
  }).then(value=>{if(!ignore)setData(value);}).catch(e=>{if(!ignore)setError(String(e.message));}).finally(()=>{if(!ignore)setLoading(false);});
  return()=>{ignore=true;abort.abort();};
 },[token,refresh]);
 async function login(event:FormEvent<HTMLFormElement>){
  event.preventDefault();const form=new FormData(event.currentTarget);setLoading(true);setError('');
  try{const r=await fetch(`${base}/auth/monitor-login`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:form.get('email'),password:form.get('password')})});
   if(!r.ok)throw new Error('Verifica tus credenciales y que tu cuenta tenga perfil de propietario.');const body=await r.json() as {token:string};setToken(body.token);
  }catch(e){setError(e instanceof Error?e.message:'No se pudo iniciar sesión.');}finally{setLoading(false);}
 }
 const payments=data?.transactions.filter(p=>!period||p.created_at.startsWith(period))??[];
 return <><a className="skip" href="#main">Ir al contenido</a><header><a className="brand" href="/">ParkLink<span>Propietarios</span></a><div className="header-end"><span className="pill">Solo consulta</span>{token?<button className="secondary" onClick={()=>{setToken(null);setData(null);}}>Cerrar sesión</button>:null}</div></header>
 <main id="main">{!token?<div className="login-layout"><section><p className="eyebrow">TU ESPACIO. TU ACTIVIDAD.</p><h1>Una mirada clara<br/>a tu estacionamiento.</h1><p className="intro">Espacios, reservas e ingresos en un solo lugar. La gestión de tus publicaciones sigue en la aplicación móvil.</p></section><form onSubmit={login}><h2>Acceso de propietarios</h2><label>Correo<input name="email" type="email" required autoComplete="username"/></label><label>Contraseña<input name="password" type="password" required autoComplete="current-password"/></label><button type="submit" aria-busy={loading}>{loading?'Ingresando…':'Consultar mi actividad'}</button>{error?<p role="alert">{error}</p>:null}</form></div>:<>
 <div className="page-title"><div><p className="eyebrow">PANEL DE MONITOREO</p><h1>Tu actividad, al día.</h1><p>Última consulta: {data?`${date.format(new Date(data.observedAt))} · Lima`:'Sin datos todavía'}</p></div><button className="secondary" onClick={()=>setRefresh(v=>v+1)} aria-busy={loading}>{loading?'Consultando…':'Actualizar datos'}</button></div>
 {error?<div className="notice" role="alert">{error} {data?'Los datos anteriores pueden estar desactualizados.':''}</div>:null}
 {data?<><section className="stats" aria-label="Resumen"><article className="balance"><p>Ingresos netos acumulados</p><strong>{money(data.income)}</strong><span>Pagos aprobados menos devoluciones procesadas. No equivale a un desembolso bancario.</span></article><article><p>Espacios publicados</p><strong>{data.spaces.total}</strong><span>{data.spaces.active} activos · {data.spaces.total-data.spaces.active} inactivos o en revisión</span></article><article><p>Reservas en curso</p><strong>{data.reservations.active}</strong><span>{data.reservations.pending} pendientes de pago · {data.reservations.confirmed} próximas</span></article><article><p>Reservas completadas</p><strong>{data.reservations.completed}</strong><span>{data.occupiedSpaces} espacios ocupados ahora</span></article></section>
 {data.truncated?<p role="status" className="notice">Consulta limitada a las últimas 500 operaciones. Los totales visibles pueden ser parciales.</p>:null}
 <div className="two-columns"><section className="panel"><h2>Ingresos por periodo</h2><p>Importes netos agrupados por mes de creación del pago.</p><div className="bars">{Object.entries(data.byMonth).length?Object.entries(data.byMonth).sort(([a],[b])=>a.localeCompare(b)).map(([month,value])=><div className="bar-row" key={month}><span>{month}</span><meter min={0} max={Math.max(1,...Object.values(data.byMonth))} value={value} aria-label={`${month}: ${money(value)}`}/><strong>{money(value)}</strong></div>):<p>Los ingresos aparecerán después de un pago aprobado.</p>}</div></section><section className="panel"><h2>Próximas reservas</h2>{data.upcoming.length?<ul className="reservations">{data.upcoming.map(r=><li key={r.id}><div><strong>{r.code}</strong><p>{date.format(new Date(r.start_time))}</p></div><span>{money(r.amount)}</span></li>)}</ul>:<p>No tienes reservas próximas confirmadas.</p>}</section></div>
 <section className="panel"><h2>Mis espacios</h2><p>Para publicar o modificar un espacio, usa ParkLink en tu teléfono.</p><div className="inventory">{data.inventory.length?data.inventory.map(s=><article key={s.id}><span className="parking-symbol" aria-hidden="true">P</span><div><h3>{s.body.title}</h3><p>{s.body.address}</p><span>{s.state} · {s.body.active?'Habilitado':'Suspendido'}</span></div><strong>{money(s.body.hourlyRate)} / h</strong></article>):<p>Todavía no publicaste espacios.</p>}</div></section>
 <section className="panel"><div className="section-heading"><h2>Historial de transacciones</h2><label>Mes<input type="month" value={period} onChange={e=>setPeriod(e.target.value)}/></label></div><div className="table-scroll"><table><caption>Pagos y devoluciones de tus estacionamientos. Todos los importes están en PEN.</caption><thead><tr><th>Fecha · Lima</th><th>Estado</th><th>Importe</th><th>Devuelto</th><th>Proveedor</th></tr></thead><tbody>{payments.length?payments.map(p=><tr key={p.id}><td>{date.format(new Date(p.created_at))}</td><td>{p.status}</td><td>{money(p.amount)}</td><td>{money(p.refunded_amount)}</td><td>{p.provider==='sandbox'?'Sandbox · sin dinero real':p.provider}</td></tr>):<tr><td colSpan={5}>Sin transacciones en este periodo.</td></tr>}</tbody></table></div></section></>:<p role="status">{loading?'Consultando tus microservicios…':'No se han recibido datos. Puedes reintentar la consulta.'}</p>}
 </>}</main><footer>ParkLink · Monitoreo para propietarios · Horarios de Lima (UTC−5)</footer></>;
}
createRoot(document.getElementById('root')!).render(<App/>);
