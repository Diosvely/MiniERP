import Link from './Link'

// Estado vacío que guía: icono, frase y la SIGUIENTE ACCIÓN (un botón que lleva a la pantalla donde se resuelve).
//   <Empty icon="🧾" text="Aún no has configurado los impuestos" action="Configurar impuestos" to="/empresa/…/taxes" />
export default function Empty({ icon = '○', text, help, action, to, onAction }) {
  return (
    <div className="vacio">
      <span className="vacio-icono" aria-hidden="true">{icon}</span>
      <p>{text}</p>
      {help && <p className="ayuda">{help}</p>}
      {action && to && <Link to={to} className="boton">{action}</Link>}
      {action && !to && onAction && <button type="button" onClick={onAction}>{action}</button>}
    </div>
  )
}
