// Enlace interno de la app (#/…): se puede abrir en otra pestaña, copiar y usar con el teclado
export default function Link({ to, children, ...rest }) {
  return <a href={`#/${to.replace(/^\/+/, '')}`} {...rest}>{children}</a>
}
