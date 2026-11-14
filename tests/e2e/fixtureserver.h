/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Shared by the e2e binaries: the Python fixture HTTP server
 * (tests/fixtures/httpd/server.py) as a subprocess, and blocking helpers
 * to query it and to read back a rendered page.
 */
#pragma once

#include <QByteArray>
#include <QEventLoop>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QString>
#include <QTcpSocket>
#include <QTimer>
#include <QtWebEngineCore/QWebEnginePage>

// Runs the script named by IFRAME_FIXTURE_HTTPD on an OS-chosen port; the
// server announces the port as one "LISTEN <port>" line on stdout.
class FixtureServer
{
public:
    bool start()
    {
        const QByteArray script = qgetenv("IFRAME_FIXTURE_HTTPD");
        if (script.isEmpty()) return false;
        m_proc.setProgram(QStringLiteral("python3"));
        m_proc.setArguments({QString::fromLocal8Bit(script),
                             QStringLiteral("--port"), QStringLiteral("0")});
        m_proc.start();
        if (!m_proc.waitForStarted(5000)) return false;
        if (!m_proc.waitForReadyRead(5000)) return false;
        const QByteArray line = m_proc.readLine();
        const QList<QByteArray> parts = line.trimmed().split(' ');
        if (parts.size() != 2 || parts[0] != "LISTEN") return false;
        bool ok = false;
        m_port = parts[1].toInt(&ok);
        return ok && m_port > 0;
    }
    void stop()
    {
        if (m_proc.state() == QProcess::Running) {
            m_proc.terminate();
            if (!m_proc.waitForFinished(2000)) m_proc.kill();
        }
    }
    int port() const { return m_port; }
    QString baseUrl() const
    {
        return QStringLiteral("http://127.0.0.1:%1").arg(m_port);
    }

private:
    QProcess m_proc;
    int m_port = 0;
};

// Blocking GET that doesn't pull in Qt::Network's access manager. Returns
// the body bytes, empty on any failure.
inline QByteArray rawGet(int port, const QByteArray &path)
{
    QTcpSocket sock;
    sock.connectToHost(QHostAddress::LocalHost, port);
    if (!sock.waitForConnected(2000)) return {};
    sock.write("GET " + path + " HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n");
    if (!sock.waitForBytesWritten(2000)) return {};
    QByteArray buf;
    while (sock.waitForReadyRead(2000)) buf.append(sock.readAll());
    const int blank = buf.indexOf("\r\n\r\n");
    return blank < 0 ? QByteArray() : buf.mid(blank + 4);
}

// The fixture's /_report as parsed JSON: what the server actually saw
// (the page body is unreliable when ErrorPageEnabled is off and a 401
// retry has occurred).
inline QJsonObject fetchReport(int port)
{
    return QJsonDocument::fromJson(rawGet(port, "/_report")).object();
}

// The page's rendered text; empty if it did not arrive within 5 s.
inline QString pageBody(QWebEnginePage &page)
{
    QString out;
    QEventLoop loop;
    page.toPlainText([&out, &loop](const QString &s) {
        out = s; loop.quit();
    });
    QTimer::singleShot(5000, &loop, &QEventLoop::quit);
    loop.exec();
    return out;
}
