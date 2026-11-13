import UIKit
import CoreImage

final class ExportViewController: UIViewController {
    private let server = LocalExportServer()
    private let titleLabel = UILabel()
    private let infoLabel = UILabel()
    private let urlLabel = UILabel()
    private let qrImageView = UIImageView()
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1.0)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        titleLabel.text = "Exportar Marcadores y Contraseñas"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white

        infoLabel.text = "Escanea el código QR con tu iPhone o abre esta dirección en tu navegador (en la misma red Wi-Fi):"
        infoLabel.font = .systemFont(ofSize: 26, weight: .regular)
        infoLabel.textColor = .lightGray
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        urlLabel.text = "Iniciando servidor local..."
        urlLabel.font = .monospacedSystemFont(ofSize: 34, weight: .semibold)
        urlLabel.textColor = .systemTeal

        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 16
        qrImageView.clipsToBounds = true
        qrImageView.widthAnchor.constraint(equalToConstant: 320).isActive = true
        qrImageView.heightAnchor.constraint(equalToConstant: 320).isActive = true

        closeButton.setTitle("Cerrar", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 44, bottom: 16, right: 44)
        closeButton.layer.cornerRadius = 14
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .primaryActionTriggered)

        [titleLabel, infoLabel, urlLabel, qrImageView, closeButton].forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 100),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -100)
        ])

        server.start { [weak self] urlString in
            guard let self = self else { return }
            if let urlString = urlString {
                self.urlLabel.text = urlString
                self.qrImageView.image = self.generateQRCode(from: urlString)
            } else {
                self.urlLabel.text = "No se pudo obtener la IP local (verifica tu conexión Wi-Fi/Ethernet)"
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        server.stop()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .ascii)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return UIImage(ciImage: scaled)
    }
}
