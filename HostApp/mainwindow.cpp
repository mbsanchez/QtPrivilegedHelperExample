// -----------------------------------------------------------------------------------
// ! @author mbsanchez
// ! @date 22/04/2016
//
// Copyright 2016 mbsanchez. All rights reserved.
//
// This file is part of PrivilegedHelperExample.
//
// PrivilegedHelperExample is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License version 2
// as published by the Free Software Foundation.
//
// PrivilegedHelperExample is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program (see the file LICENSE included with this
// distribution); if not, write to the Free Software Foundation, Inc.,
// 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
// or see http://www.gnu.org/licenses/.
// -----------------------------------------------------------------------------------

#include "smjobbless.h"
#include "mainwindow.h"
#include "ui_mainwindow.h"
#include <QMessageBox>
#include "smjobbless.h"

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow)
{
    ui->setupUi(this);
}

MainWindow::~MainWindow()
{
    delete ui;
}

void MainWindow::on_m_bnInstallHelper_clicked()
{
    HelperToolResult res = installPrivilegedHelperTool();
    if (res != HT_INSTALL_FAILED) {
        QMessageBox::information(this, "Success!", "PrivilegedHelper tool installed successfully!\n");
        initConnection();
    }else
        QMessageBox::critical(this, "Failure :(", "PrivilegedHelper tool not installed");
}

void MainWindow::on_m_bnCallHelper_clicked()
{
    runExampleTool();
}
